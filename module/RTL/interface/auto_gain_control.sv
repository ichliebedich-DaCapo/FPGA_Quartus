module auto_gain_control (
    input        adc_clk,     // ADC采样时钟（200MHz+）
    input        rst_n,       // 异步复位
    input [11:0] adc_data,    // ADC数据（0-2000mV）
    output reg [1:0] gain_ctrl, // 增益控制[一级,二级]
    output reg      stable     // 稳定指示
);

// ================== 参数定义 ====================
parameter STABLE_CYCLES = 5;  // 需连续5个稳定周期
parameter SAMPLE_NUM    = 512; // 采样点数
parameter OVERLOAD_ADC  = 3944;// 1925mV对应ADC值

// 增益档位阈值（单位：ADC码值）
typedef struct {
    logic [11:0] lower;
    logic [11:0] upper;
} threshold_t;

threshold_t THRESHOLDS[4] = '{
    // [291.666667,600mV] →3x →[875mV,1800mV]
    '{lower:1792, upper:3686}, // 档位00
    // [134.615385,291.666667] →6.5x →[875mV,1895.83mV]
    '{lower:1792, upper:3884}, // 档位01
    // [64.814815,134.615385] →13.5x →[875mV,1817.307mV]
    '{lower:1792, upper:3723}, // 档位10
    // [30mV,64.814815] → 29.25x → [877.5mV,1895.83mV]
    '{lower:1798, upper:3884}  // 档位11
};
    
// ================== 状态定义 ====================
typedef enum logic [1:0] {
    IDLE,
    SAMPLING,
    CALCULATE,
    ADJUST
} state_t;

// ================== 寄存器声明 ====================
state_t         current_state, next_state;
reg [9:0]       sample_counter;
reg [11:0]      max_value, min_value;
reg [11:0]      peak_value;
reg [1:0]       target_gain;
reg [3:0]       stable_counter;
reg             overload_flag;

// ================== 组合逻辑 =====================
// 下一状态计算
always_comb begin
    next_state = current_state;
    case(current_state)
        IDLE:     next_state = SAMPLING;
        SAMPLING: begin
            if(sample_counter == SAMPLE_NUM-1) 
                next_state = CALCULATE;
            else
                next_state = SAMPLING;
        end
        CALCULATE: next_state = ADJUST;
        ADJUST:   next_state = IDLE;
        default:  next_state = IDLE;
    endcase
end

// ================== 时序逻辑 =====================
always_ff @(posedge adc_clk or negedge rst_n) begin
    if(!rst_n) begin
        current_state   <= IDLE;
        sample_counter  <= 0;
        max_value       <= 0;
        min_value       <= 4095;
        peak_value      <= 0;
        gain_ctrl       <= 2'b00;
        target_gain     <= 2'b00;
        stable_counter  <= 0;
        overload_flag   <= 0;
    end else begin
        current_state <= next_state;
        overload_flag <= (adc_data > OVERLOAD_ADC);

        case(current_state)
            IDLE: begin
                sample_counter <= 0;
                max_value      <= adc_data;
                min_value      <= adc_data;
            end

            SAMPLING: begin
                sample_counter <= sample_counter + 1;
                max_value      <= (adc_data > max_value) ? adc_data : max_value;
                min_value      <= (adc_data < min_value) ? adc_data : min_value;
            end

            CALCULATE: begin
                peak_value <= max_value - min_value;
            end

            ADJUST: begin
                // 过载紧急处理
                if(overload_flag) begin
                    target_gain <= (gain_ctrl > 0) ? (gain_ctrl - 1) : gain_ctrl;
                    stable_counter <= 0;
                end
                // 常规调整
                else begin
                    if(peak_value > THRESHOLDS[gain_ctrl].upper) begin
                        target_gain <= (gain_ctrl > 0) ? (gain_ctrl - 1) : gain_ctrl;
                        stable_counter <= 0;
                    end
                    else if(peak_value < THRESHOLDS[gain_ctrl].lower) begin
                        target_gain <= (gain_ctrl < 3) ? (gain_ctrl + 1) : gain_ctrl;
                        stable_counter <= 0;
                    end
                    else begin
                        target_gain <= gain_ctrl;
                        stable_counter <= (stable_counter < STABLE_CYCLES) ? stable_counter + 1 : stable_counter;
                    end
                end

                // 更新输出寄存器
                gain_ctrl <= target_gain;
            end
        endcase
    end
end

assign stable = (stable_counter == STABLE_CYCLES);

endmodule