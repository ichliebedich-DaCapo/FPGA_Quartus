module auto_gain_control (
    input clk,// 看门狗系统所需时钟
    input adc_clk,
    input rst_n,
    input [11:0] adc_data,
    output reg [1:0] relay_ctrl,
    output reg stable
);

// 增益参数定义
localparam GAIN_3     = 2'd0; // relay_ctrl=2'b00
localparam GAIN_6_5   = 2'd1; // relay_ctrl=2'b01
localparam GAIN_13_5  = 2'd2; // relay_ctrl=2'b10
localparam GAIN_29_25 = 2'd3; // relay_ctrl=2'b11
// 增益映射表修正（索引与增益对应）
localparam logic [1:0] GAIN_MAP[4] = '{
    GAIN_3     : 2'b00,
    GAIN_6_5   : 2'b01,
    GAIN_13_5  : 2'b10,
    GAIN_29_25 : 2'b11
};
// 过压阈值（1925mV对应的ADC值）
localparam OVER_VOLTAGE_THRESHOLD = 12'd3941;

// 增益上下限结构体
typedef struct {
    logic [11:0] lower; // 对应区间的下限ADC值
    logic [11:0] upper; // 对应区间的上限ADC值
} gain_limit_t;

// 增益上下限查找表
gain_limit_t gain_limits[4];
initial begin
    // [30mV,64.814815] → 29.25x → [877.5mV,1895.83mV]
    gain_limits[0].lower = 12'd1798; // 877.5mV
    gain_limits[0].upper = 12'd3883; // 1895.83mV
    // [64.814815,134.615385] →13.5x →[875mV,1817.307mV]
    gain_limits[1].lower = 12'd1791; // 875mV
    gain_limits[1].upper = 12'd3723; // 1817.307mV
    // [134.615385,291.666667] →6.5x →[875mV,1895.83mV]
    gain_limits[2].lower = 12'd1791;
    gain_limits[2].upper = 12'd3883;
    // [291.666667,600mV] →3x →[875mV,1800mV]
    gain_limits[3].lower = 12'd1791;
    gain_limits[3].upper = 12'd3685; // 1800mV
end

// 检测窗口大小（例如1000个采样点）
localparam SAMPLE_WINDOW_SIZE = 512;
localparam PEAK_SAMPLE_NUM = 8;     // 取8个最高峰值
localparam PEAK_INDEX_BITS = $clog2(PEAK_SAMPLE_NUM);
localparam WAIT_STABLE_DELAY = 5;
reg [3:0] wait_counter;

// 峰值存储结构
reg [11:0] peak_samples [0:PEAK_SAMPLE_NUM-1];
reg [PEAK_INDEX_BITS-1:0] peak_ptr;
reg [12:0] peak_sum; // 12bit*8=15bit

// 状态机定义
enum logic [2:0] {
    RESET,
    READY,// 准备状态，等待进入采样时刻
    SAMPLING,
    EVALUATE,
    ADJUST,
    WAIT_STABLE
} state;

reg [1:0] current_gain_idx;
reg [9:0] sample_count; // 存储512个采样点
reg [1:0] next_gain_idx;

// 防止adc_clk一直为低电平。主时钟200M，而采样频率最低可达100K，即相差2000倍，取极端情况，2000*100
// 看门狗参数
localparam WATCHDOG_TIMEOUT = 20'hFFFFF; // 200*1000 @200MHz -> 1KHz
reg [19:0] watchdog_counter;
reg adc_clk_prev;  // 同步寄存器
wire adc_clk_changed;
reg watchdog_timeout;

// 同步块
always @(posedge clk ) begin
    adc_clk_prev <= adc_clk;// 同步寄存器
    watchdog_timeout <= (watchdog_counter >= WATCHDOG_TIMEOUT);
end

assign adc_clk_changed = (adc_clk ^ adc_clk_prev);// adc_clk变化检测
wire adc_clk_rising = ~adc_clk & adc_clk_prev;// adc_clk下降沿

// 看门狗计数器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        watchdog_counter <= 0;
    end else if (adc_clk_changed) begin
        watchdog_counter <= 0;  // 检测到时钟活动时重置
    end else if (watchdog_counter < WATCHDOG_TIMEOUT) begin
        watchdog_counter <= watchdog_counter + 1;
    end
end

// 全局复位信号
wire global_reset_n = rst_n & ~watchdog_timeout;


// 【注意】：这里是假定采样频率为1K以上，如果低于这个频率，那么这里的运算逻辑需要移送至主时钟域200MHz
reg is_overvoltage;// 过压条件
always @(posedge adc_clk or negedge global_reset_n) begin
    if(!global_reset_n)begin
        state <= RESET;// 初始状态
        current_gain_idx <= GAIN_3;// 初始最低增益
        relay_ctrl <= GAIN_MAP[GAIN_3];
        stable <= 0;
        peak_sum <= 0;
        sample_count <= 0;
        wait_counter <= 0;
        is_overvoltage <= 0;
        // 清空峰值队列
        for(int i=0; i<PEAK_SAMPLE_NUM; i=i+1) begin
            peak_samples[i] <= 0;
        end
    end else begin
        case (state)
            RESET: begin
                // 初始化采样参数
                state <= SAMPLING;
                peak_sum <= 0;
                sample_count <= 0;
                wait_counter <= 0;
                is_overvoltage <= 0;
                // 清空峰值队列
                for(int i=0; i<PEAK_SAMPLE_NUM; i=i+1) begin
                    peak_samples[i] <= 0;
                end
            end
            READY: begin
                if(adc_clk_rising)begin
                    state <= SAMPLING;// 进入采样阶段
                end else begin
                    state <= READY;
                end
            end
            SAMPLING: begin
                // 检查过压条件
                if (adc_data >= OVER_VOLTAGE_THRESHOLD) begin
                    // 立即调低增益
                    current_gain_idx <= (current_gain_idx > GAIN_3) ? current_gain_idx - 1 : current_gain_idx;
                    relay_ctrl <= GAIN_MAP[current_gain_idx];

                    // 迅速再次检测
                    is_overvoltage <= 1;
                    state <= READY;
                    sample_count <=0;
                    stable <= 0;    // 不稳定
                end else begin
                    // 维护峰值队列
                    if(adc_data > peak_samples[PEAK_SAMPLE_NUM-1]) begin
                        // 插入排序更新峰值队列，8个必然会满
                        for(int i=PEAK_SAMPLE_NUM-2; i>=0; i--) begin
                            if(adc_data > peak_samples[i]) begin
                                peak_samples[i+1] = peak_samples[i];
                            end else begin
                                peak_samples[i+1] = adc_data;
                                break;
                            end
                        end
                        peak_samples[0] <= adc_data;
                    end

                    // 检测窗口结束
                    if (sample_count == SAMPLE_WINDOW_SIZE-1)
                        state <= EVALUATE;
                    else 
                        sample_count <= sample_count + 1;
                end
            end
            // 评估结果
            EVALUATE: begin
                // 计算峰值平均值
                automatic logic [15:0] sum_temp = 0;
                for(int i=0; i<PEAK_SAMPLE_NUM; i=i+1) begin
                    sum_temp = sum_temp + peak_samples[i];
                end
                peak_sum <= sum_temp[15:3]; // 除以8

                // 比较峰值
                if (peak_sum > gain_limits[current_gain_idx].upper) begin
                    // 调低增益
                    next_gain_idx <= (current_gain_idx > GAIN_3) ? current_gain_idx - 1 : current_gain_idx;
                    state <= ADJUST;
                end else if (peak_sum < gain_limits[current_gain_idx].lower) begin
                    // 调高增益
                    next_gain_idx <= (current_gain_idx < GAIN_29_25) ? current_gain_idx + 1 : current_gain_idx;
                    state <= ADJUST;
                end else begin
                    // 无需调整，重新采样
                    stable <= 1;// 说明很稳定
                    state <= READY;
                    sample_count <= 0;
                    // 清空峰值队列
                    for(int i=0; i<PEAK_SAMPLE_NUM; i=i+1) begin
                        peak_samples[i] <= 0;
                    end
                end
            end

            // 调整增益，说明不稳定
            ADJUST: begin
                // 更新增益
                current_gain_idx <= next_gain_idx;
                // 设置继电器控制信号
                relay_ctrl <= GAIN_MAP[next_gain_idx];
                stable <= 0;// 不稳定

                if(is_overvoltage)begin
                    state <= RESET;
                end else begin
                    state <= WAIT_STABLE;
                end
            end

            WAIT_STABLE: begin
                if(adc_clk_rising)begin
                    if (wait_counter >=WAIT_STABLE_DELAY) begin
                        state <= RESET;
                        stable <= 1;// 标记为稳定，等下轮评估结果再决定稳不稳定                
                    end else begin
                        wait_counter <= wait_counter + 1;
                    end
                 end
            end

            default: state <= RESET;
        endcase
    end
end

endmodule