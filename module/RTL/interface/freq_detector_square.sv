// 【简介】：基于电压比较器的频率检测模块
// 【Fmax】：240MHz
// 【note】：输入信号为1K~100K，考虑到信号并不是很高，如果使用等精度测量法会有相当大的延迟，于是使用了周期测量法。
//  并且由于Fmax达到200MHz以上，那么这个模块可以很轻松地连接上200MHz的时钟。
// 【details】：此处所说误差其实是偏差，也就是实际信号的频率会稍微波动一下，且此处所说误差是按照f的比率，而非相对误差。
//          固定误差法：周期误差为δ（也就是THRESHOLD），有f'=(200M)/(P+δ)，那么测得频率 f' = (200M)/(200M+δ*f)*f，会受f影响
//              δf = 20M →  f'误差:-9.1%~11.1%   δ:500~20K
//              δf = 10M →  f'误差:-4.7%~5.3%    δ:250~10K
//          动态误差法：周期误差比例为δ（也就是0.5^THRESH_SHIFT），有f'=(200M)/(P*(1+δ))，那么f'的比例误差为1/(1+δ)，不会受f影响
//              δ = 6.25% →  f'比例误差:-5.9%~6.7%          THRESH_SHIFT = 4
//              δ = 3.125% →  f'比例误差:-3.0%~3.2%         THRESH_SHIFT = 5
module freq_detector_square #(
    parameter STABLE_CYCLES = 4,// 连续稳定计数器，也就是说连续STABLE_CYCLES次，周期都在误差范围允许内
    parameter THRESH_SHIFT = 5, // 阈值=周期值>>5 → 3.125%
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
reg signal_posedge;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        signal_in_prev <= 1'b0;
        signal_posedge <= 1'b0;
    end else begin
        signal_in_prev <= signal_in;
        signal_posedge <= ~signal_in_prev & signal_in;
    end
end

//━━━━━━━━━━━━━━ 周期计数器（边沿触发重置）━━━━━━━━━━━━━━━
reg [COUNTER_WIDTH-1:0] cycle_cnt;
reg [COUNTER_WIDTH-1:0] captured_cycle;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cycle_cnt <= 0;
        captured_cycle <= 0;
    end else if (signal_posedge) begin
        captured_cycle <= cycle_cnt;    // 保存当前计数值
        cycle_cnt <= '1;                 // 重置时补偿当前周期（+1在else分支）
    end else begin
        cycle_cnt <= cycle_cnt + 1'b1;  // 持续计数
    end
end

//━━━━━━━━━━━━ 周期缓冲区（存储最近4周期）━━━━━━━━━━━━
reg [COUNTER_WIDTH-1:0] period_buf [4];
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        period_buf[0] <= 0;
        period_buf[1] <= 0;
        period_buf[2] <= 0;
        period_buf[3] <= 0;
    end else if (signal_posedge) begin
        // 手动实现移位寄存器
        period_buf[3] <= captured_cycle;  // 新值插入最高位
        period_buf[2] <= period_buf[3];   // 原[3]→[2]
        period_buf[1] <= period_buf[2];   // 原[2]→[1]
        period_buf[0] <= period_buf[1];   // 原[1]→[0]
    end
end

//━━━━━━━━━━━━ 动态阈值计算 ━━━━━━━━━━━━
reg [COUNTER_WIDTH+1:0] sum_period;
wire [COUNTER_WIDTH-1:0] avg_period = sum_period[COUNTER_WIDTH+1:2]; // 除4运算
reg [COUNTER_WIDTH-1:0] dynamic_thresh ;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sum_period <= 0;
        dynamic_thresh <= 0;
    end else begin
        sum_period <= period_buf[0] + period_buf[1] + period_buf[2] + period_buf[3];
        dynamic_thresh = avg_period >> THRESH_SHIFT;
    end
end

//━━━━━━━━━━━━ 稳定性检测逻辑 ━━━━━━━━━━━━
// 多插入几级流水线，反正由于更新计数器就需要不少周期，足以检测稳定性了
reg [3:0] valid_flags; // 各周期有效标志
reg valid;
reg p0_low,p0_up,p1_low,p1_up,p2_low,p2_up,p3_low,p3_up;
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 异步复位所有时序逻辑
        valid_flags <= 4'b0000;  // 清空有效标志
        valid        <= 1'b0;     // 有效信号复位
        // 以下临时变量复位可选（根据设计需求）
        p0_low      <= 1'b0;     
        p0_up       <= 1'b0;
        p1_low      <= 1'b0;
        p1_up       <= 1'b0;
        p2_low      <= 1'b0;
        p2_up       <= 1'b0;
        p3_low      <= 1'b0;
        p3_up       <= 1'b0;
    end else begin
        // 组合逻辑部分（建议独立为always_comb）
        /* 推荐将比较逻辑移至always_comb块 */
        // 周期0的上下界比较
        p0_low = (period_buf[0] >= (avg_period - dynamic_thresh));
        p0_up  = (period_buf[0] <= (avg_period + dynamic_thresh));
        
        // 周期1的上下界比较  
        p1_low = (period_buf[1] >= (avg_period - dynamic_thresh));
        p1_up  = (period_buf[1] <= (avg_period + dynamic_thresh));
        
        // 周期2的上下界比较
        p2_low = (period_buf[2] >= (avg_period - dynamic_thresh));
        p2_up  = (period_buf[2] <= (avg_period + dynamic_thresh));
        
        // 周期3的上下界比较
        p3_low = (period_buf[3] >= (avg_period - dynamic_thresh));
        p3_up  = (period_buf[3] <= (avg_period + dynamic_thresh));

        // 时序逻辑部分
        valid_flags[0] <= p0_low && p0_up;  // 标志位0有效性
        valid_flags[1] <= p1_low && p1_up;  // 标志位1有效性
        valid_flags[2] <= p2_low && p2_up;  // 标志位2有效性
        valid_flags[3] <= p3_low && p3_up;  // 标志位3有效性
        valid          <= &valid_flags;     // 全部标志有效时置位
    end
end

//━━━━━━━━━━━━ 稳定状态机 ━━━━━━━━━━━━
reg [2:0] stable_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        stable_cnt <= 0;
    end else if (valid) begin  // 所有周期均有效
        if (stable_cnt < STABLE_CYCLES) 
            stable_cnt <= stable_cnt + 1'b1;
    end else begin
        stable_cnt <= 0;
    end
end



always_ff@(posedge clk)begin
    period <= avg_period;        // 输出平均周期
    stable <= (stable_cnt == STABLE_CYCLES);
end

endmodule