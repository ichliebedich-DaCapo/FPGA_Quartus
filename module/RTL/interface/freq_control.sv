// 【简介】频率控制模块
// 【Fmax】：266.1MHz
// 【表格】：需要主时钟达到48MHz
//         区间范围    采样率          分频系数
//        [1K,2K)     24K             1000
//        [2K,4K)     48K             500
//        [4K,8K)     96K             250
//        [8K,16K)    192K            125
//        [16K,32K)   384K->400K      62.5->60
//        [32K,64K)   768K->800K      31.25->30
//        [64K,128K)  1536K->1600K    15.625->15
module freq_control #(
    parameter COUNTER_WIDTH = 18, 
    parameter DIV_WIDTH     = 12
) (
    input clk,
    input rst_n,
    input en,// 稳定信号，频率检测均为稳定的信号
    input [COUNTER_WIDTH-1:0] period,
    output reg [DIV_WIDTH-1:0] div,
    output reg stable
);
localparam FREQ_24K = 999;
localparam FREQ_48K = 499;
localparam FREQ_96K = 249;
localparam FREQ_192K = 124;
localparam FREQ_400K = 59;
localparam FREQ_800K = 29;
localparam FREQ_1600K = 14;

reg en_prev;  // 用于检测en的上升沿

// 检测en的上升沿
wire en_rise = en && !en_prev;
reg [DIV_WIDTH-1:0] div_new;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        en_prev <= 1'b0;
        div <= FREQ_1600K;  // 初始分频系数设为15,确保ADC可以检测指定区间的任何信号
        stable <= 1'b1;
    end else begin
        en_prev <= en;  // 更新en_prev
        if (en_rise) begin  // 仅在en的上升沿处理
            // 根据period确定新的分频系数div_new
            // 根据period的区间判断分频系数
            if (period > 100000 && period <= 200000)
                div_new = FREQ_24K;
            else if (period > 50000 && period <= 100000)
                div_new = FREQ_48K;
            else if (period > 25000 && period <= 50000)
                div_new = FREQ_96K;
            else if (period > 12500 && period <= 25000)
                div_new = FREQ_192K;
            else if (period > 6250 && period <= 12500)
                div_new = FREQ_400K;
            else if (period > 3125 && period <= 6250)
                div_new = FREQ_800K;
            else if (period > 1562 && period <= 3125)
                div_new = FREQ_1600K;
            else 
                div_new = div;  // 不在任何区间则保持当前值

            // 判断是否需要更新分频系数
            if (div_new != div) begin
                div <= div_new;  // 更新分频系数
                stable <= 1'b0;  // 切换时拉低stable
            end else begin
                stable <= 1'b1;  // 无需切换时保持高
            end
        end else begin
            stable <= 1'b1;  // 非上升沿时stable保持高
        end
    end
end

endmodule