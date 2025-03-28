`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_sdma;

// =========================================时钟周期定义======================================
parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
parameter                           HALF_CLK_PERIOD           = 0.5;
logic clk;
logic finsh;
integer count;
initial begin
    clk = 0; // @200MHz
    finsh = 0;
    count =0;
    fork
        begin : loop_block
            forever begin
                #HALF_CLK_PERIOD clk = ~clk; // 每个周期翻转一次
                if(clk)begin
                    count = count + 1;
                end
                if (finsh == 1'b1) begin
                    disable loop_block; // 使用 disable 退出
                end
            end
        end
    join
end
// =========================================时钟周期定义======================================
logic rst_n;
// 信号定义


// 参数定义
parameter DATA_WIDTH = 12;
localparam BUF_SIZE = 1024;
localparam READ_STATE_ADDR = 16'h4000;
// 信号声明
wire [17:0] AD;
reg NADV;
reg NWE;
reg NOE;
reg [11:0] adc_data;
reg signal_in;
reg [1:0]gain_ctrl;
reg adc_clk;
reg ADC_OE;

logic ad_dir;
wire [17:0]  ad_in;                                   // 内部信号，用于控制 ad
logic [17:0]  ad_out;
assign ad_in =AD;
assign AD = ad_dir ?ad_out : 18'bz;

// 实例化被测模块
sdma sdma(
    .AD(AD),
    .NADV(NADV),
    .NWE(NWE),
    .NOE(NOE),
    .clk(clk),
    .rst_n(rst_n),
    .adc_data(adc_data),
    .signal_in(signal_in),
    .gain_ctrl(gain_ctrl),
    .adc_clk(adc_clk),
    .ADC_OE(ADC_OE)
);

// ===================初始设置==================
initial begin
    rst_n = 1'b1;
    // 初始化所有输入信号
    ad_dir =0;
    ad_out = 18'bz;
    NADV = 1'b1;
    NWE = 1'b1;
    NOE = 1'b1;
    adc_data = 0;
    signal_in = 0;
    gain_ctrl = 'z;
    #10 rst_n = 1'b0;
    #10 rst_n = 1'b1;


    // $display("==================test:1==================");
    // read_data();
    // $display("==================test:2==================");
    // read_data();
    // $display("==================test:3==================");
    // read_data();
    

    #10000;
    // 结束仿真 
    finsh = 1'b1;
end

// ======================================ADC数据生成==========================================
initial begin
    #20;
    for (int i = 0; i < 100; i++) begin
        generate_adc(i*10);
        #10;
    end
    // 结束仿真 
    $display("=========ADC_Done==========");
    finsh = 1'b1;
end

// 生成ADC数据
task generate_adc(input [11:0] offset = 0);
begin
    // 启动采集条件
    signal_in =0;
    @(posedge clk);
    signal_in = 1;
    @(posedge clk);
    
    // 生成ADC数据（简单递增模式）
    for (int i=0; i<BUF_SIZE; i++) begin
        adc_data = i[11:0]+offset;
        @(posedge adc_clk);
    end
end
endtask
    
// 读取数据
// task read_data();
// begin
//     wait(uut.has_switched)
//     $display("%d--> ready to read data : ptr:%d",count,uut.write_ptr);
//     fsmc_read(READ_STATE_ADDR);// 获取状态
//     fsmc_write(READ_STATE_ADDR,1);// 写入1，表示正在读取
//     for (int i=0; i<BUF_SIZE; i++) begin
//         fsmc_read(i);
//     end
//     fsmc_write(READ_STATE_ADDR,0);// 写入0，表示读取完成
// end
// endtask

// 写操作测试
task mcu_write(input [17:0] addr,input [15:0]data);
begin
    #5;
    // ----------写地址------------
    // 拉低地址片选
    NADV =0;
    ad_dir =1;//开始写
    ad_out = addr;// 写入地址
    #5;

    // 拉低NWE
    NWE =0;
    NADV =1;
    #3;

    // 地址保持时间
    #1;
    ad_dir =0;
    #2;

    // ----------写数据------------
    // 写入数据
    ad_dir =1;
    ad_out = {2'b0,data};
    #10;

    //  写入结束
    NWE =1;
    // 保持时间
    #3;
    ad_dir =0;
    $display("---------->[data]:%h",ad_in);
    #8;
end
endtask

task mcu_read(input [17:0] addr,input [15:0]module_data);
begin
    #5;
    // ----------写地址------------
    NADV =0;// 先拉低地址片选
    ad_dir =1;//开始写
    ad_out = addr;// 写入地址
    #6;
    
    // 拉高地址片选
    NADV =1;// 此时应该拉低NWE
    // 保持时间
    #4;
    ad_dir =0;
    ad_out = module_data;
    #5;

    // ----------读数据------------
    // 拉低NOE
    NOE =0;
    #8;
    NOE =1;
    #1;
    $display("---------->[data]:%h",ad_in);
    #8;
end
endtask


// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    // $monitor("time:%t switch:%d  buf:%d reg_read:%d",$time,uut.has_switched,uut.write_buf,uut.reg_read);
end

endmodule