module auto_gain_control (
    input clk,            // 主时钟（目标300MHz+）
    input adc_clk,        // ADC时钟（假设<20MHz）
    input rst_n,
    input [11:0] adc_data,
    output reg [1:0] relay_ctrl,
    output reg stable
);

// 同步ADC数据到主时钟域
reg [11:0] adc_data_sync;
always @(posedge clk) begin
    adc_data_sync <= adc_data; // 双寄存器同步化（根据实际需求可增加）
end

// 增益阈值预计算（FS=2V对应4096 LSB）
localparam HYSTERESIS = 12'd50;    // 滞回窗口
localparam STABLE_CYCLES = 3'd4;   // 稳定周期数（需≥adc_clk周期/clk周期）

typedef enum logic [1:0] { 
    GAIN_29_25 = 2'b11,
    GAIN_13_5  = 2'b10,
    GAIN_6_5   = 2'b01,
    GAIN_3     = 2'b00 
} gain_state_t;

// 状态寄存器（主时钟驱动）
gain_state_t current_gain, next_gain;
reg [2:0] stable_counter;
reg [11:0] adc_th_low, adc_th_high;

// 预存储增益阈值（LSB值）
always @(posedge clk) begin
    case(current_gain)
        GAIN_29_25: begin
            adc_th_low  <= 12'd1797; // 877.5mV
            adc_th_high <= 12'd3885; // 1895.83mV
        end
        GAIN_13_5: begin
            adc_th_low  <= 12'd1792; // 875mV
            adc_th_high <= 12'd3723; // 1817.3mV
        end
        GAIN_6_5: begin
            adc_th_low  <= 12'd1792;
            adc_th_high <= 12'd3885;
        end
        GAIN_3: begin
            adc_th_low  <= 12'd1792;
            adc_th_high <= 12'd3686; // 1800mV
        end
    endcase
end

// 滞回比较器（寄存器输出）
reg over_high, below_low;
always @(posedge clk) begin
    over_high <= (adc_data_sync + HYSTERESIS) >= adc_th_high;
    below_low <= adc_data_sync < (adc_th_low - HYSTERESIS);
end

// 增益状态转移逻辑（组合）
always_comb begin
    next_gain = current_gain;
    if(over_high) begin
        case(current_gain)
            GAIN_29_25: next_gain = GAIN_13_5;
            GAIN_13_5:  next_gain = GAIN_6_5;
            GAIN_6_5:   next_gain = GAIN_3;
            default: ; 
        endcase
    end else if(below_low) begin
        case(current_gain)
            GAIN_3:    next_gain = GAIN_6_5;
            GAIN_6_5:   next_gain = GAIN_13_5;
            GAIN_13_5:  next_gain = GAIN_29_25;
            default: ;
        endcase
    end
end

// 主状态机（三级流水优化）
reg [1:0] state;
localparam S_IDLE = 2'd0;
localparam S_WAIT_STABLE = 2'd1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        current_gain <= GAIN_29_25;
        stable <= 1'b0;
        stable_counter <= STABLE_CYCLES;
        state <= S_IDLE;
    end else begin
        case(state)
            S_IDLE: begin
                if(current_gain != next_gain) begin
                    current_gain <= next_gain;
                    stable <= 1'b0;
                    stable_counter <= STABLE_CYCLES;
                    state <= S_WAIT_STABLE;
                end else begin
                    stable <= 1'b1;
                end
            end
            S_WAIT_STABLE: begin
                if(stable_counter > 0) begin
                    stable_counter <= stable_counter - 1;
                end else begin
                    state <= S_IDLE;
                end
            end
        endcase
    end
end

// 输出继电器控制
assign relay_ctrl = current_gain;

endmodule