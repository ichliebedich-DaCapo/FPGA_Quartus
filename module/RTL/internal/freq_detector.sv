// 【简介】基于过零检测的频率检测模块
// 【note】过零检测不应有窗口限制
module freq_detector #(
    parameter DATA_WIDTH = 12        // 输入/输出数据位宽
)(
    input               adc_clk,     // ADC时钟域
    input               rst_n,       // 异步复位
    input signed [DATA_WIDTH-1:0] data_in,  // 去直流后的有符号数据
    output reg [DATA_WIDTH-1:0] period,     // 周期数据
    output reg          stable              // 频率稳定指示
);

// 流水线阶段控制信号
reg [2:0] stage;

// 输入数据寄存（阶段1）
reg signed [DATA_WIDTH-1:0] data_prev;
always @(posedge adc_clk or negedge rst_n)
    if (!rst_n) data_prev <= 0;
    else        data_prev <= data_in;

// 过零检测（阶段2）
wire zero_cross = (data_prev[DATA_WIDTH-1] ^ data_in[DATA_WIDTH-1]);
wire direction = data_prev > data_in; // 1: 正到负，0: 负到正

// 有效过零事件检测（阶段3）
reg [1:0] valid_cross_pipe;
always @(posedge adc_clk or negedge rst_n)
    if (!rst_n) valid_cross_pipe <= 2'b00;
    else        valid_cross_pipe <= {valid_cross_pipe[0], zero_cross};

wire valid_cross = valid_cross_pipe[1];

// 周期计数器（阶段4）
reg [DATA_WIDTH:0] counter;  // 扩展1bit防止溢出
reg [DATA_WIDTH:0] prev_counter;
reg last_direction;

always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        counter      <= 0;
        prev_counter <= 0;
        last_direction <= 0;
    end else begin
        if (valid_cross) begin
            // 方向交替时更新周期
            if (direction != last_direction) begin
                prev_counter <= counter;
                counter      <= 0;
                last_direction <= direction;
            end
        end else begin
            counter <= counter + 1;
        end
    end
end

// 周期计算（阶段5）
reg [DATA_WIDTH:0] period_temp;
always @(posedge adc_clk or negedge rst_n)
    if (!rst_n) period_temp <= 0;
    else if (valid_cross)
        period_temp <= prev_counter + counter;

// 稳定性检测（阶段6）
reg [DATA_WIDTH:0] prev_period;
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        period    <= 0;
        prev_period <= 0;
        stable    <= 0;
    end else if (valid_cross) begin
        period    <= period_temp[DATA_WIDTH-1:0];
        prev_period <= period;
        stable    <= (period_temp == {prev_period, 1'b0});
    end
end

endmodule