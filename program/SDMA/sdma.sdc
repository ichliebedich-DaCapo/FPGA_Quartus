# 基本时钟定义 @25MHz
create_clock -name clk -period 40 [get_ports clk]

# 200MHz时钟定义 @200MHz
create_clock -name clk_200 -period 5 [get_ports clk_200]

# 48MHz时钟定义 @48MHz
create_clock -name clk_48 -period 20.8 [get_ports clk_48]

# ADC时钟定义 @10MHz
create_clock -name adc_clk -period 100 [get_ports adc_clk]

