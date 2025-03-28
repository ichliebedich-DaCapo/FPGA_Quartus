// 【简介】：信号失真度检测模块
// 【功能】：可供单片机读取信号的周期、增益、频率控制和周期，也可连续读取1024个ADC数据
// 【Fmax】：204MHz
module sdma(
    // ================= 物理接口 =================
    inout  [17:0] AD,                   // 复用地址/数据总线
    input         NADV,                 // 地址有效指示（低有效）
    input         NWE,                  // 写使能（低有效）
    input         NOE,                  // 读使能（低有效）
    
    // ================= 系统接口 =================
    input         clk,                  // 主时钟
    input         rst_n,                // 异步复位

    // ================= 外部接口 =================
    input [11:0] adc_data,      // ADC数据
    input signal_in,            // 方波信号输入，输入的是来自电压比较器的信号
    output [1:0] gain_ctrl,     // 增益控制
    output       adc_clk,       // ADC时钟，需要输出到高速ADC中
    output       ADC_OE         // ADC输出使能（低电平有效）
);

// ---------FSMC接口信号---------
reg sync_rst_n;// 同步复位信号
wire [15:0] rd_data;
wire [15:0] wr_data_0;
wire [15:0] wr_data_1;
wire [3:0] cs;
wire addr_en, rd_en, wr_en;

// ---------子模块信号---------
wire [11:0]div;
wire[11:0] sync_adc_data;// 同步后的ADC数据
reg sync_signal_in;
wire gain_stable,freq_stable,freq_detector_stable;
wire stable = gain_stable & freq_stable;
wire [17:0]period;

// ---------锁相信号---------
wire clk_200,clk_48,locked;
pll_c0_200_c1_48	pll(
	.areset (~rst_n),
	.inclk0 ( clk ),
	.c0 ( clk_200 ),
	.c1 ( clk_48 ),
	.locked ( locked )
);

//  同步模块
always @(posedge clk) begin
    sync_rst_n <= rst_n & locked;
    sync_signal_in <= signal_in;
end

// ===================================FSMC接口模块======================================
fsmc_interface fsmc(
    .AD(AD),
    .NADV(NADV),
    .NWE(NWE),
    .NOE(NOE),
    .clk(clk_200),
    .rst_n(sync_rst_n),
    .rd_data(rd_data),
    .wr_data_array('{wr_data_1,wr_data_0}),// 起始放在右边
    .cs(cs),
    .addr_en(addr_en),
    .rd_en(rd_en),
    .wr_en(wr_en)
);

// ===================================子模块======================================
// --------双缓冲模块--------
dual_buffer dual_buffer(
    .clk(clk_200),
    .rst_n(sync_rst_n),
    .en(cs[0]),
    .addr_en(addr_en),
    .rd_en(rd_en),
    .wr_en(wr_en),
    .rd_data(rd_data),
    .wr_data(wr_data_0),
    .adc_clk(adc_clk),
    .sync_adc_data(sync_adc_data),
    .stable(stable),
    .sync_signal_in(sync_signal_in)
);

// --------波形信息模块--------
wave_information wave_info(
    .clk(clk_200),
    .rst_n(sync_rst_n),
    .en(cs[1]),
    .addr_en(addr_en),
    .rd_en(rd_en),
    .wr_en(wr_en),
    .rd_data(rd_data),
    .wr_data(wr_data_1),
    .div(div),
    .gain_ctrl(gain_ctrl),
    .period(period)
);

// ===================================接口/内部模块======================================


// --------增益程控模块--------
auto_gain_control auto_gain_ctrl(
    .clk(clk_200),
    .adc_clk(adc_clk),
    .rst_n(sync_rst_n),
    .adc_data(sync_adc_data),
    .relay_ctrl(gain_ctrl),
    .stable(gain_stable)
);

// --------频率控制模块--------
freq_control freq_control(
    .clk(clk_200),
    .rst_n(sync_rst_n),
    .en(freq_detector_stable),
    .period(period),
    .div(div),
    .stable(freq_stable)
);
// 频率检测模块
freq_detector_square freq_detector(
    .clk(clk_200),
    .rst_n(sync_rst_n),
    .signal_in(signal_in),
    .period(period),
    .stable(freq_detector_stable)
);

// --------ADC接口模块--------
adc_interface adc_interface(
    .adc_clk(adc_clk),
    .rst_n(sync_rst_n),
    .ADC_DATA(adc_data),
    .DATA_OUT(sync_adc_data),
    .ADC_OE(ADC_OE)
);

// --------分频器模块--------
divider divider(
    .clk(clk_48),
    .rst_n(sync_rst_n),
    .div(div),
    .adc_clk(adc_clk)
);

endmodule