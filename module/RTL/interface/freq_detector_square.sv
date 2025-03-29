// 【简介】：基于电压比较器的频率检测模块
// 【Fmax】：246MHz
// 【note】：输入信号为1K~100K，考虑到信号并不是很高，如果使用等精度测量法会有相当大的延迟，于是使用了周期测量法。
//  并且由于Fmax达到200MHz以上，那么这个模块可以很轻松地连接上200MHz的时钟。
// 【details】：周期误差为δ，待测信号实际频率为f，那么测得频率 f' = (200M)/(200M+δ*f)*f，由于噪声存在，输入信号的不同频率对这个阈值的要求也不同
//              δf = 20M →  f'误差:-9.1%~11.1%   δ:500~20K
//              δf = 10M →  f'误差:-4.7%~5.3%    δ:250~10K
module freq_detector_square #(
    parameter STABLE_CYCLES = 4,// 
    parameter THRESHOLD = 250, // 允许的最大周期差
    parameter COUNTER_WIDTH  = 18     // 根据200MHz/1kHz=200_000计算（2^18=262,144）
)(
    input               clk,    
    input               rst_n,       // 异步复位
    input               signal_in,    // 输入的是已经同步后的方波信号
    output reg  [COUNTER_WIDTH-1:0] period,// 周期计数器输出
    output reg stable   // 稳定标志，高电平表示频率稳定
);

// 边沿检测
reg signal_in_prev;
wire signal_posedge = ~signal_in_prev & signal_in;
always @(posedge clk) begin
    signal_in_prev <= signal_in;
end

// 周期计数器（优化位宽减少逻辑延迟）
reg [COUNTER_WIDTH-1:0] cycle_cnt;
reg [COUNTER_WIDTH-1:0] captured_cycle;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_cnt <= 0;
        captured_cycle <= 0;
    end else if (signal_posedge) begin
        captured_cycle <= cycle_cnt + '1; // 补偿计数+1
        cycle_cnt <= 0;
    end else begin
        cycle_cnt <= cycle_cnt + '1;
    end
end

// 历史存储优化
localparam  HISTORY_SIZE = 4; // 历史周期数存储深度
reg [COUNTER_WIDTH-1:0] history [0:HISTORY_SIZE-1];
// 并行获取历史数据
wire [COUNTER_WIDTH-1:0] h0 = history[0];
wire [COUNTER_WIDTH-1:0] h1 = history[1];
wire [COUNTER_WIDTH-1:0] h2 = history[2];
wire [COUNTER_WIDTH-1:0] h3 = history[3];
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        period <= 0;
        history[0] <= 0;
        history[1] <= 0;
        history[2] <= 0;
        history[3] <= 0;
    end else if (signal_posedge) begin
        history[0] <= captured_cycle;
        history[1] <= history[0];
        history[2] <= history[1]; 
        history[3] <= history[2];
    end else begin
        period <= (history[1] + history[2]) >> 1;
    end
end

// 差异检查优化（并行比较+流水线）
reg [HISTORY_SIZE-2:0] diff_ok;
reg h0_up,h0_down,h1_up,h1_down,h2_up,h2_down;
always @(posedge clk) begin
    // 并行比较
    h0_down <=  (h0 >= h1 - THRESHOLD);
    h0_up <=  (h0 <= h1 + THRESHOLD);
    h1_down <=  (h1 >= h2 - THRESHOLD);
    h1_up <=  (h1 <= h2 + THRESHOLD);
    h2_down <=  (h2 >= h3 - THRESHOLD);
    h2_up <=  (h2 <= h3 + THRESHOLD);
    diff_ok[0] <= h0_down && h0_up;
    diff_ok[1] <= h1_down && h1_up;
    diff_ok[2] <= h2_down && h2_up;
end



wire all_diff_ok = &diff_ok;

// 稳定计数器优化（专用加法器）
reg [$clog2(STABLE_CYCLES+1)-1:0] stable_cnt;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        stable_cnt <= 0;
    end else if (signal_posedge) begin
        case ({all_diff_ok, (stable_cnt < STABLE_CYCLES)})
            2'b11: stable_cnt <= stable_cnt + 1'b1;
            2'b10: stable_cnt <= STABLE_CYCLES;
            default: stable_cnt <= 0;
        endcase
    end
end

// 稳定信号输出（寄存器输出）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) stable <= 0;
    else stable <= (stable_cnt >= STABLE_CYCLES);
end

endmodule