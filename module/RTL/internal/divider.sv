// 【简介】分频模块
// 【功能】：可进行任意整数次分频，前提是输入时钟频率为你要进行分频的那个基频的两倍
// 【Fmax】：291.29MHz，去除异步复位后，反而只有270MHz
module divider #(
    parameter DIV_WIDTH = 12
)(
    input wire clk,          // 输入时钟,确保是要进行任意整数次分频的基频的两倍
    input wire rst_n,          // 复位信号
    input wire [DIV_WIDTH-1:0] div,    // 12位宽的话，0到4095分频
    output reg ADC_CLK       // 输出时钟
);

reg [DIV_WIDTH-1:0] count;            // 计数器（支持最大分频系数1000）

// 分频器核心逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin        // 复位或sel变化时初始化
        count <= 0;
        ADC_CLK <= 1'b0;
    end else if(count == div) begin
    // 0-9共10个状态，即10分频
        count <= 0;
        ADC_CLK <= ~ADC_CLK;
    end else begin
        count <= count + 1;
    end
end

endmodule