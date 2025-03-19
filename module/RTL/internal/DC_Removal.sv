// 去直流模块——流水线设计
// 针对的是周期信号，既然是周期信号，那么均值稳定，历史数据的均值对当下也同样适用
module DC_Removal #(
    parameter DATA_WIDTH = 12,       // 输入/输出数据位宽
    parameter AVG_WINDOW = 1024      // 平均窗口大小,必须为2的幂次
)(
    input  wire adc_clk,            // ADC时钟（下降沿有效）
    input  wire stable,             // 系统稳定信号
    input  wire [DATA_WIDTH-1:0] data_in,
    output reg signed [DATA_WIDTH:0] data_out, // 扩展符号位
    output reg en   // 高电平有效
);

localparam SHIFT = $clog2(AVG_WINDOW);
localparam SUM_WIDTH = DATA_WIDTH + SHIFT + 1; // 增加符号位

// 符号扩展处理
reg signed [SUM_WIDTH-1:0] sum = 0;
reg [DATA_WIDTH:0] avg_reg = 0;
reg [9:0] counter = 0;
wire signed [DATA_WIDTH:0] signed_data = {1'b0, data_in}; // 无符号转有符号

always_ff @(posedge adc_clk or negedge stable) begin
    if (!stable) begin
        sum <= 0;
        counter <= 0;
        avg_reg <= 0;
        data_out <= 0;
        en <= 0;
    end else begin
        // 默认累加
        sum <= sum + signed_data;
        counter <= counter + 1;

        // 窗口结束处理
        if (counter == AVG_WINDOW-1) begin
            avg_reg <= (sum + signed_data) >>> SHIFT; // 包含当前数据
            sum <= 0;
            counter <= 0;
            en <= 1;// 稳定后，平均值即可使用，去直流有效
        end

        // 去直流计算（保持符号）
        data_out <= signed_data - avg_reg; // 结果范围：-2048~+2047
    end
end
endmodule