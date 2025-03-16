# 基本时钟定义 @200MHz
create_clock -name clk -period 5 [get_ports clk]

# ADC时钟定义 @10MHz
create_clock -name adc_clk -period 100 [get_ports adc_clk]

