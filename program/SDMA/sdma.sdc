# 主时钟定义 @25MHz（输入时钟）
create_clock -name clk -period 40 [get_ports clk]

# PLL生成的200MHz时钟（使用生成时钟约束） @200MHz
# 前者指向PLL的输出引脚 后者指定内部时钟网络
create_generated_clock -name clk_200 -source [get_pins pll/c0] [get_nets clk_200]                  

# PLL生成的48MHz时钟@48MHz（使用生成时钟约束）
create_generated_clock -name clk_48 -source [get_pins pll/c1] [get_nets clk_48]

# ADC时钟定义 @10MHz
create_clock -name adc_clk -period 50 [get_ports adc_clk]
# create_generated_clock -name adc_clk -source [get_pins divider/clk] -master_clock clk_48 -divide_by 30 [get_nets adc_clk]

