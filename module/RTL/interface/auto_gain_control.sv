// 【简介】自动增益程控模块
module auto_gain_control (
    input adc_clk,
    input rst_n,
    input [11:0] adc_data,
    output reg [1:0] gain_ctrl,
    output reg stable
);

// 增益参数定义
localparam GAIN_3     = 2'd0; // gain_ctrl=2'b00
localparam GAIN_6_5   = 2'd1; // gain_ctrl=2'b01
localparam GAIN_13_5  = 2'd2; // gain_ctrl=2'b10
localparam GAIN_29_25 = 2'd3; // gain_ctrl=2'd11
// 增益映射表（增益与实际继电器开关对应）
localparam logic [1:0] GAIN_MAP[4] = '{2'b00,2'b01,2'b10,2'b11};
// 过压阈值（1925mV对应的ADC值）
localparam OVER_VOLTAGE_THRESHOLD = 12'd3941;

// 增益上下限结构体
typedef struct {
    logic [11:0] lower; // 对应区间的下限ADC值（峰峰值）
    logic [11:0] upper; // 对应区间的上限ADC值（峰峰值）
} gain_limit_t;

// 增益上下限查找表（修改为峰峰值范围）
localparam gain_limit_t GAIN_LIMITS[4] = '{
    // [291.666667,600mV] →3x →[875mV,1800mV]（峰峰值范围）
    GAIN_3: '{lower: 12'd1791, upper: 12'd3685},  // 对应于3x增益
    // [134.615385,291.666667] →6.5x →[875mV,1895.83mV]（峰峰值范围）
    GAIN_6_5: '{lower: 12'd1791, upper: 12'd3883}, // 对应于6.5x增益
    // [64.814815,134.615385] →13.5x →[875mV,1817.307mV]（峰峰值范围）
    GAIN_13_5: '{lower: 12'd1791, upper: 12'd3723}, // 对应于13.5x增益
    // [30mV,64.814815] → 29.25x → [877.5mV,1895.83mV]（峰峰值范围）
    GAIN_29_25: '{lower: 12'd1798, upper: 12'd3883} // 对应于29.25x增益
};

// 检测窗口大小（例如512个采样点）
localparam SAMPLE_WINDOW_SIZE = 512;
localparam STABLE_COUNTER_THRESHOLD = 3;
localparam WAIT_STABLE_CYCLES = 10;
reg [1:0] stable_counter;
assign stable = (stable_counter >= STABLE_COUNTER_THRESHOLD);
reg [3:0] wait_counter;

// 峰峰值检测相关寄存器
reg [11:0] peak;   // 窗口内最大值
reg [11:0] valley; // 窗口内最小值（初始设为最大可能值）
reg [11:0] pp_value;// 计算峰峰值（新增核心逻辑）
// 状态机定义
enum logic [2:0] {
    RESET,
    SAMPLING,
    EVALUATE,
    ADJUST,
    WAIT_STABLE
} state;

reg [1:0] current_gain_idx;
reg [9:0] sample_count; // 存储512个采样点
reg [1:0] next_gain_idx;
reg sample_done,is_adc_overload;
reg is_pp_value_big;// 峰峰值是否大
reg is_pp_value_small;// 峰峰值是否小

// 增加一级输入寄存器
reg [11:0] adc_data_reg;
reg [11:0] pp_value_sync;
// 延迟一拍的采样数据
reg [11:0] adc_data_dly;
always @(posedge adc_clk) begin
    pp_value_sync <= pp_value;
    adc_data_reg <= adc_data;
    adc_data_dly <= adc_data_reg;
end
// 同步比较逻辑
reg update_peak, update_valley;
always_ff @(posedge adc_clk)begin
    sample_done <= sample_count == SAMPLE_WINDOW_SIZE-1;
    pp_value <= peak - valley;
    is_adc_overload <= adc_data_reg >= OVER_VOLTAGE_THRESHOLD;
    is_pp_value_big <= pp_value_sync > GAIN_LIMITS[current_gain_idx].upper;
    is_pp_value_small <= pp_value_sync < GAIN_LIMITS[current_gain_idx].lower;
    update_peak <= (adc_data_reg > peak);
    update_valley <= (adc_data_reg < valley);
end


// 主逻辑（修改为峰峰值检测）
always @(posedge adc_clk or negedge rst_n) begin
    if(!rst_n)begin
        state <= RESET;
        current_gain_idx <= GAIN_3;
        gain_ctrl <= GAIN_MAP[GAIN_3];
        peak <= '0;
        valley <= 12'hFFF; // 初始化为最大值以便后续比较
        stable_counter <= 0;
        sample_count <=0;
        wait_counter <= 0;
    end else begin
        case (state)
            RESET: begin
                // 初始化采样参数
                state <= SAMPLING;
                peak <= 0;
                valley <= 12'hFFF;
                stable_counter <= 0;
                sample_count <=0;
            end
            SAMPLING: begin
                // 过压保护（保持原有瞬时值检测）
                if (is_adc_overload) begin
                    next_gain_idx <= (current_gain_idx > GAIN_3) ?current_gain_idx - 1'b1 : current_gain_idx;
                    state <= ADJUST;
                end else begin
                    // 并行更新峰值和谷值（新增最小值检测）
                    if(update_peak) peak <= adc_data_dly;
                    if(update_valley) valley <= adc_data_dly;

                    // 窗口采样结束判断
                    if (sample_done) begin
                        state <= EVALUATE;
                    end else begin
                        sample_count <= sample_count + 1'b1;
                    end
                end
            end
            EVALUATE: begin
                // 根据峰峰值调整增益
                if (is_pp_value_big) begin
                    next_gain_idx <= (current_gain_idx > GAIN_3) ? current_gain_idx - 1'b1 : current_gain_idx;
                    state <= ADJUST;
                end else if (is_pp_value_small) begin
                    next_gain_idx <= (current_gain_idx < GAIN_29_25) ?current_gain_idx + 1'b1 : current_gain_idx;
                    state <= ADJUST;
                end else begin
                    if (stable_counter < STABLE_COUNTER_THRESHOLD) begin
                        stable_counter <= stable_counter + 1'b1;
                    end
                    // 重置峰峰值、采样计数器
                    state <= SAMPLING;
                    sample_count <=0;
                    peak <='0;
                    valley <= 12'hFFF; 
                end
            end
            ADJUST: begin
                // 增益调整
                current_gain_idx <= next_gain_idx;
                gain_ctrl <= GAIN_MAP[next_gain_idx];
                wait_counter <= 0;
                state <= WAIT_STABLE;// 重置参数逻辑全部放在RESET里了
            end
            WAIT_STABLE:begin
                if (wait_counter >= WAIT_STABLE_CYCLES) begin
                    state <= RESET;
                end else begin
                    wait_counter <= wait_counter + 1;
                end
            end
            default: state <= RESET;
        endcase
    end
end

endmodule