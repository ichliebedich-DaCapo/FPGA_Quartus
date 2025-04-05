// 【修正说明】
// 1. 修复peak和valley多驱动问题，统一在峰值检测模块处理
// 2. 优化状态机转换逻辑
// 3. 修复增益边界判断逻辑
// 4. 补充必要寄存器初始化

// 【简介】自动增益程控模块（时序优化修正版）
module auto_gain_control (
    input         adc_clk,     // ADC采样时钟
    input         rst_n,       // 异步复位，低有效
    input  [11:0] adc_data,    // ADC采样数据
    output reg [1:0] gain_ctrl,// 增益控制信号
    output reg    stable       // 稳定状态指示
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
    '{lower: 12'd1791, upper: 12'd3685},  // GAIN_3
    // [134.615385,291.666667] →6.5x →[875mV,1895.83mV]
    '{lower: 12'd1791, upper: 12'd3883}, // GAIN_6_5
    // [64.814815,134.615385] →13.5x →[875mV,1817.307mV]
    '{lower: 12'd1791, upper: 12'd3723}, // GAIN_13_5
    // [30mV,64.814815] → 29.25x → [877.5mV,1895.83mV]
    '{lower: 12'd1798, upper: 12'd3883}  // GAIN_29_25
};

// 检测窗口大小（512个采样点）
localparam SAMPLE_WINDOW_SIZE = 512;
localparam STABLE_COUNTER_THRESHOLD = 3;
localparam WAIT_STABLE_CYCLES = 10;

// 时序优化新增参数
localparam PIPELINE_STAGES = 2; // 关键路径流水线级数

// 峰峰值检测相关寄存器
reg [11:0] peak, peak_d1;      // 窗口内最大值（带流水线）
reg [11:0] valley, valley_d1;  // 窗口内最小值（带流水线）
reg [11:0] pp_value;           // 峰峰值计算结果
reg [11:0] pp_value_pre;       // 峰峰值预计算值

// 状态机定义（三段式优化）
enum logic [2:0] {
    RESET,        // 复位初始化
    SAMPLING,     // 数据采样
    EVALUATE,     // 信号评估
    ADJUST,       // 增益调整
    WAIT_STABLE   // 稳定等待
} state, next_state;

// 增益控制寄存器组（降低扇出）
(* keep = "true" *) reg [1:0] current_gain_idx;
reg [1:0] current_gain_idx_rep1; // 寄存器副本1
reg [1:0] current_gain_idx_rep2; // 寄存器副本2

// 同步控制寄存器
reg [9:0]  sample_count;       // 采样计数器
reg        sample_done;        // 采样完成标志
reg        is_adc_overload;    // ADC过载标志
reg        is_pp_value_big;    // 峰峰值过大标志
reg        is_pp_value_small;  // 峰峰值过小标志
reg [3:0]  wait_counter;       // 稳定等待计数器

// 输入数据流水线（两级寄存）
reg [11:0] adc_data_reg[0:1];
always @(posedge adc_clk) begin
    adc_data_reg[0] <= adc_data;     // 第一级寄存
    adc_data_reg[1] <= adc_data_reg[0]; // 第二级寄存
end

// 峰值检测流水线（统一处理多驱动问题）
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        peak   <= 12'd0;
        valley <= 12'hFFF;
        peak_d1  <= 12'd0;
        valley_d1 <= 12'hFFF;
    end else begin
        peak_d1  <= peak;
        valley_d1 <= valley;
        
        case(state)
            RESET: begin  // 复位时初始化
                peak   <= 12'd0;
                valley <= 12'hFFF;
            end
            SAMPLING: begin
                // 更新峰值
                if (adc_data_reg[1] > peak_d1) 
                    peak <= adc_data_reg[1];
                // 更新谷值
                if (adc_data_reg[1] < valley_d1)
                    valley <= adc_data_reg[1];
            end
            EVALUATE: begin // 评估结束后重置
                peak   <= 12'd0;
                valley <= 12'hFFF;
            end
            default: ; // 其他状态保持当前值
        endcase
    end
end

// 峰峰值计算流水线
always @(posedge adc_clk) begin
    pp_value_pre <= peak_d1 - valley_d1; // 预计算级
    pp_value     <= pp_value_pre;       // 输出级
end

// 状态机时序逻辑
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) state <= RESET;
    else state <= next_state;
end

// 状态机组合逻辑
always @(*) begin
    next_state = state;
    case(state)
        RESET: next_state = SAMPLING;
        
        SAMPLING: begin
            if (is_adc_overload)       next_state = ADJUST;
            else if (sample_done)      next_state = EVALUATE;
            else next_state = SAMPLING;
        end
        
        EVALUATE: begin
            if (is_pp_value_big || is_pp_value_small) 
                next_state = ADJUST;
            else 
                next_state = SAMPLING;
        end
        
        ADJUST:    next_state = WAIT_STABLE;
        
        WAIT_STABLE: begin
            if (wait_counter >= WAIT_STABLE_CYCLES) 
                next_state = RESET;
            else
                next_state = WAIT_STABLE;
        end
    endcase
end

// 同步控制信号生成
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        current_gain_idx <= GAIN_3;
        gain_ctrl        <= GAIN_MAP[GAIN_3];
        stable           <= 1'b0;
        sample_count     <= 10'd0;
        wait_counter     <= 4'd0;
        current_gain_idx_rep1 <= GAIN_3;
        current_gain_idx_rep2 <= GAIN_3;
    end else begin
        // 寄存器副本同步
        current_gain_idx_rep1 <= current_gain_idx;
        current_gain_idx_rep2 <= current_gain_idx;
        
        case(state)
            RESET: begin
                stable       <= 1'b0;
                sample_count <= 10'd0;
            end
            
            SAMPLING: begin
                sample_count <= sample_count + 1'b1;
            end
            
            EVALUATE: begin
                sample_count <= 10'd0; // 重置采样计数器
                // 稳定计数器逻辑
                if (!(is_pp_value_big || is_pp_value_small)) begin
                    if (stable < STABLE_COUNTER_THRESHOLD) 
                        stable <= stable + 1'b1;
                end else begin
                    stable <= 1'b0;
                end
            end
            
            ADJUST: begin
                current_gain_idx <= next_gain_idx;
                gain_ctrl        <= GAIN_MAP[next_gain_idx];
                wait_counter     <= 4'd0;
                stable           <= 1'b0;
            end
            
            WAIT_STABLE: begin
                wait_counter <= wait_counter + 1'b1;
            end
        endcase
    end
end

// 组合逻辑时序化
always @(posedge adc_clk) begin
    sample_done     <= (sample_count == SAMPLE_WINDOW_SIZE-1);
    is_adc_overload <= (adc_data_reg[1] >= OVER_VOLTAGE_THRESHOLD);
    // 使用副本降低扇出
    is_pp_value_big   <= (pp_value > GAIN_LIMITS[current_gain_idx_rep1].upper);
    is_pp_value_small <= (pp_value < GAIN_LIMITS[current_gain_idx_rep2].lower);
end

// 增益调整逻辑（提前计算）
reg [1:0] next_gain_idx;
always @(posedge adc_clk) begin
    if (state == EVALUATE) begin
        if (is_pp_value_big) begin
            next_gain_idx <= (current_gain_idx > GAIN_3) ? current_gain_idx - 1'b1 : GAIN_3;
        end else if (is_pp_value_small) begin
            next_gain_idx <= (current_gain_idx < GAIN_29_25) ? current_gain_idx + 1'b1 : GAIN_29_25;
        end
    end
end

endmodule