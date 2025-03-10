module adc_interface (
    input  logic        adc_clk,     // ADC时钟输入（与ADS805同步）
    input  logic        rst_n,       // 异步复位（低电平有效）
    input  logic [11:0] ADC_DATA,    // ADS805并行数据输入
    output logic [11:0] DATA_OUT,    // 同步后的数据输出
    output logic        ADC_OE       // ADS805输出使能（低电平有效）
);

// ADC输出使能控制
assign ADC_OE = ~rst_n; // 复位期间禁用ADC输出，正常工作期间使能

// 数据同步寄存器
always_ff @(posedge adc_clk or negedge rst_n) begin
    if (!rst_n) begin
        DATA_OUT <= 12'h000;        // 复位时清零输出
    end else begin
        DATA_OUT <= ADC_DATA;       // 时钟上升沿捕获数据
    end
end

endmodule