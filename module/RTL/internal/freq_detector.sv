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
reg [DATA_WIDTH:0] current_period;
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        current_period <= 0;
    end else if (cross_valid) begin
        current_period <= (last_pos + last_neg) >> 1;
    end
end

// 稳定性检测（窗口比较）
reg [DATA_WIDTH:0] period_history[0:3];
integer i;
always @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i=0; i<4; i=i+1)
            period_history[i] <= 0;
        period <= 0;
        stable <= 0;
    end else begin
        // 滑动窗口更新
        if (|current_period) begin
            period_history[0] <= current_period;
            for (i=3; i>0; i=i-1)
                period_history[i] <= period_history[i-1];
        end
        
        // 周期输出取中间值
        period <= (period_history[1] + period_history[2]) >> 1;
        
        // 稳定性判断（连续3个周期波动小于5%）
        stable <= ((period_history[3] > period_history[2]*95/100) &&
                  (period_history[3] < period_history[2]*105/100) &&
                  (period_history[2] > period_history[1]*95/100) &&
                  (period_history[2] < period_history[1]*105/100));
    end
end

endmodule