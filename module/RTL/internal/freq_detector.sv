// 【简介】基于过零检测的频率检测模块
// 【note】
//      1，过零检测受窗口限制
//      2，只需STABLE_CYCLES+2.5个被测信号周期即可判断信号是否稳定，且仅需一个被测信号周期即可判断信号是否不稳定
//      3，输入数据必须是经去直流处理后的有符号数据
//      4，rst_n可接其他模块的稳定信号，比如增益程控模块，那么逻辑就是：增益稳定后，再判断频率是否稳定。
module freq_detector #(
    parameter DATA_WIDTH = 12,        // 输入/输出数据位宽
    parameter PERIOD_WIDTH =16,        // 周期数据位宽，0~2^16-1足够覆盖任意采样频率了
    parameter STABLE_CYCLES = 3  // 确认周期数，实际上需要STABLE_CYCLES+2.5个周期才能判断周期是否稳定。只需信号的一个周期即可判断信号是否不稳定。
)(
    input               adc_clk,     // ADC时钟域
    input               rst_n,       // 异步复位
    input signed [DATA_WIDTH-1:0] data_in,  // 去直流后的有符号数据
    output reg [PERIOD_WIDTH-1:0] period,     // 周期数据
    output reg          stable              // 频率稳定指示
);

// 信号定义
reg signed [DATA_WIDTH-1:0] data_prev[0:1];
wire zero_cross = (data_prev[1][DATA_WIDTH-1] ^ data_in[DATA_WIDTH-1]);
wire direction = data_prev[1] > data_in;

// 三级流水线寄存
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        data_prev[0] <= 0;
        data_prev[1] <= 0;
    end else begin
        data_prev[0] <= data_in;
        data_prev[1] <= data_prev[0];
    end
end

// 有效过零检测（添加滤波）
reg [2:0] cross_filter;
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) cross_filter <= 0;
    else        cross_filter <= {cross_filter[1:0], zero_cross};
end

wire valid_cross = (cross_filter[2:1] == 2'b11); // 持续两周期高电平

// 周期计数器（带溢出保护）
reg [DATA_WIDTH:0] pos_counter, neg_counter;
reg [DATA_WIDTH:0] last_pos, last_neg;
reg cross_valid;

always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        pos_counter <= 1;
        neg_counter <= 1;
        last_pos <= 0;
        last_neg <= 0;
        cross_valid <= 0;
    end else begin
        // 计数器递增
        pos_counter <= pos_counter + 1;
        neg_counter <= neg_counter + 1;
        
        // 正过零检测
        if (valid_cross && direction) begin
            last_pos <= pos_counter;
            pos_counter <= 1;
            cross_valid <= 1;
        end 
        // 负过零检测
        else if (valid_cross && !direction) begin
            last_neg <= neg_counter;
            neg_counter <= 1;
            cross_valid <= 1;
        end else begin
            cross_valid <= 0;
        end
    end
end

// 周期计算（取两个半周期平均值）
reg [PERIOD_WIDTH:0] current_period;
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        current_period <= 0;
    end else if (cross_valid) begin
        current_period <= (last_pos + last_neg) >> 1;
    end
end

// 修改后的稳定性检测模块
reg [PERIOD_WIDTH:0] period_history[0:3];
reg [$clog2(STABLE_CYCLES)-1:0] stable_flags;
// 改进的稳定性判断条件
wire stable_cond1 = (period_history[0] >= period_history[1] - 1) && 
                    (period_history[0] <= period_history[1] + 1);
wire stable_cond2 = (period_history[1] >= period_history[2] - 1) && 
                    (period_history[1] <= period_history[2] + 1);
wire stable_cond3 = (period_history[2] >= period_history[3] - 1) && 
                    (period_history[2] <= period_history[3] + 1);
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        period <= 0;
        stable <= 0;
        period_history[0] <= 0;
        period_history[1] <= 0;
        period_history[2] <= 0;
        period_history[3] <= 0;
        stable_flags <= 0;
    end else if (cross_valid) begin
        // 滑动窗口更新优化
        period_history[3] <= period_history[2];
        period_history[2] <= period_history[1];
        period_history[1] <= period_history[0];
        period_history[0] <= current_period;
        
        // 中间值输出保持稳定
        period <= (period_history[1] + period_history[2]) >> 1;
        
        // 稳定性标志累加器
        if (stable_cond1 && stable_cond2 && stable_cond3) begin
            stable_flags <= (stable_flags == STABLE_CYCLES) ? STABLE_CYCLES : stable_flags + 1;
        end else begin
            stable_flags <= 0;
        end
        
        // 稳定信号输出
        stable <= (stable_flags >= STABLE_CYCLES);
    end
end

endmodule