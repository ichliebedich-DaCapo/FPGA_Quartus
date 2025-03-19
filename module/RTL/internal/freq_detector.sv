// 基于过零检测的频率检测模块
module freq_detector #(
    parameter DATA_WIDTH = 12,       // 输入/输出数据位宽
    parameter WINDOW = 1024,         // 平均窗口大小,必须为2的幂次
    parameter TOLERANCE = 2          // 周期稳定性容差
)(
    input               adc_clk,            // ADC时钟域
    input               rst_n,              // 异步复位
    input signed [DATA_WIDTH-1:0] data_in,  // 去直流后的有符号数据
    output reg [DATA_WIDTH-1:0] period,     // 周期数据
    output reg          stable              // 频率稳定指示
);

    reg signed [DATA_WIDTH-1:0] data_in_prev; // 延迟一拍的输入数据
    wire zero_cross;                         // 过零检测信号
    reg [9:0] window_counter;                // 窗口计数器（0~1023）
    reg [10:0] zc_counter;                   // 过零计数器（最大1024次）
    reg [10:0] zc_count_stored;              // 存储窗口内的过零次数
    reg [DATA_WIDTH-1:0] prev_period;        // 前一周期的值
    reg window_done;                         // 窗口结束标志（延迟一拍）
    localparam DIV_SCALE = 16;               // 除法精度扩展
    reg [DATA_WIDTH+DIV_SCALE-1:0] period_scaled; // 扩展精度周期计算

    // 过零检测：符号位不同表示过零点
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) data_in_prev <= 0;
        else        data_in_prev <= data_in;
    end
    assign zero_cross = (data_in_prev[DATA_WIDTH-1] != data_in[DATA_WIDTH-1]);

    // 窗口计数与过零统计（含边界过零）
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            window_counter <= 0;
            zc_counter <= 0;
            zc_count_stored <= 0;
        end else begin
            window_counter <= (window_counter == WINDOW - 1) ? 0 : window_counter + 1;

            if (zero_cross) begin
                zc_counter <= zc_counter + 1;
            end

            if (window_counter == WINDOW - 1) begin
                zc_count_stored <= zc_counter + (zero_cross ? 1 : 0);
                zc_counter <= 0;
            end
        end
    end

    // 高精度周期计算（定点数近似）
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            period <= 0;
            period_scaled <= 0;
        end else begin
            if (zc_count_stored == 0) begin
                period <= 0; // 处理无过零情况
            end else begin
                period_scaled <= (WINDOW * 2 * (2**DIV_SCALE)) / zc_count_stored;
                period <= period_scaled[DIV_SCALE +: DATA_WIDTH]; // 截取整数部分
            end
        end
    end

    // 窗口结束标志
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) window_done <= 0;
        else        window_done <= (window_counter == WINDOW - 1);
    end

    // 带容差的稳定性判断
    always @(posedge adc_clk or negedge rst_n) begin
        if (!rst_n) begin
            stable <= 0;
            prev_period <= 0;
        end else if (window_done) begin
            stable <= ((period >= prev_period - TOLERANCE) && 
                      (period <= prev_period + TOLERANCE)) || 
                      (period == prev_period);
            prev_period <= period;
        end
    end

endmodule