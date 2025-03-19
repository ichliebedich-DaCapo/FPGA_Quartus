// 【简介】：基于电压比较器的频率检测模块
module freq_detector_square #(
    parameter STABLE_CYCLES = 4,// 
    parameter HISTORY_SIZE = 4, // 历史周期数存储深度
    parameter THRESHOLD = 1, // 允许的最大周期差
    parameter COUNTER_WIDTH  = 18     // 根据200MHz/1kHz=200_000计算（2^18=262,144）
)(
    input               clk,    
    input               rst_n,       // 异步复位
    input               signal_in,    // 输入方波信号
    output reg stable   // 稳定标志，高电平表示频率稳定
);

// 边沿检测优化（增加打拍减少亚稳态）
reg [1:0] signal_sync;
always @(posedge clk) begin
    signal_sync <= {signal_sync[0], signal_in};
end
wire signal_posedge = (signal_sync[1] & ~signal_sync[0]);

// 周期计数器（优化位宽减少逻辑延迟）
reg [COUNTER_WIDTH-1:0] cycle_cnt;
reg [COUNTER_WIDTH-1:0] captured_cycle;
always @(posedge clk) begin
    if (signal_posedge) begin
        captured_cycle <= cycle_cnt;
        cycle_cnt <= 0;
    end else begin
        cycle_cnt <= cycle_cnt + 1;
    end
end

// 历史存储优化（指针式访问替代移位）
reg [COUNTER_WIDTH-1:0] history [0:HISTORY_SIZE-1];
reg [$clog2(HISTORY_SIZE)-1:0] hist_ptr;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        hist_ptr <= 0;
        for (int i=0; i<HISTORY_SIZE; i=i+1)
            history[i] <= 0;
    end else if (signal_posedge) begin
        hist_ptr <= hist_ptr + 1;
        history[hist_ptr] <= captured_cycle;
    end
end

// 差异检查优化（并行比较+流水线）
reg [HISTORY_SIZE-2:0] diff_ok;
// 并行获取历史数据
wire [COUNTER_WIDTH-1:0] h0 = history[hist_ptr];
wire [COUNTER_WIDTH-1:0] h1 = history[hist_ptr-1];
wire [COUNTER_WIDTH-1:0] h2 = history[hist_ptr-2];
wire [COUNTER_WIDTH-1:0] h3 = history[hist_ptr-3];
always @(posedge clk) begin
    // 并行比较（关键路径优化）
    diff_ok[0] <= (h0 >= h1 - THRESHOLD) && (h0 <= h1 + THRESHOLD);
    diff_ok[1] <= (h1 >= h2 - THRESHOLD) && (h1 <= h2 + THRESHOLD);
    diff_ok[2] <= (h2 >= h3 - THRESHOLD) && (h2 <= h3 + THRESHOLD);
end
wire all_diff_ok = &diff_ok;

// 稳定计数器优化（专用加法器）
reg [$clog2(STABLE_CYCLES+1)-1:0] stable_cnt;
always @(posedge clk) begin
    if (signal_posedge) begin
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
    else        stable <= (stable_cnt >= STABLE_CYCLES);
end

endmodule