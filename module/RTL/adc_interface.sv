module adc_interface (
    input  logic        adc_clk,    // ADC时钟输入
    input  logic        rst_n,      // 异步复位，低电平有效
    input  logic [11:0] adc_data,   // ADC数据总线（假设12位）
    output logic [11:0] data_out,   // 同步输出数据
    output logic        data_valid  // 数据有效脉冲
);

// 寄存器缓存前一个周期的drdy状态
logic drdy_prev;

always_ff @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        drdy_prev <= 1'b0;
    end else begin
        drdy_prev <= adc_drdy;
    end
end

// 检测数据就绪信号的上升沿
logic drdy_rise;
assign drdy_rise = adc_drdy && !drdy_prev;

// 数据捕获逻辑
always_ff @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out   <= 12'h000;
        data_valid <= 1'b0;
    end else begin
        data_valid <= 1'b0;  // 默认无效
        if (drdy_rise) begin
            data_out   <= adc_data;  // 捕获有效数据
            data_valid <= 1'b1;      // 生成有效脉冲
        end
    end
end

endmodule