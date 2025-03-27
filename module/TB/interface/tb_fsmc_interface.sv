// `define DEBUG


module tb_fsmc_interface;

// =========================================时钟周期定义======================================
parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
parameter                           HALF_CLK_PERIOD           = 0.5;
parameter                           HALF_ADC_CLK_MULT         = 10; // ADC_CLK与CLK相差的倍数的一半
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

    // 信号定义
    logic reset;
    logic nadv;                                             // MCU ----> 地址有效信号，低电平有效
    logic nwe;                                              // MCU ----> 写有效信号，低电平有效
    logic noe;                                              // MCU ----> 读有效信号，低电平有效
                                        // MCU <---> 地址和数据复用线 (AD17-AD0)
    logic [15:0]  module_out;                          // 内部信号，用于控制 module_ad
    logic [15:0]  module_out2;
    logic [15:0]  module_in;


    logic [3:0]cs;
    logic addr_en,rd_en,wr_en;

    // 定义线
    logic ad_dir;
    wire  [17:0] ad;    
    wire [17:0]  ad_in;                                   // 内部信号，用于控制 ad
    logic [17:0]  ad_out;


    assign ad_in =ad;
    assign ad = ad_dir ?ad_out : 18'bz;

    // **************用于测试*****************


    // 被测模块实例化
    fsmc_interface uut (
    .clk(clk),
    .NADV(nadv),
    .NOE(noe),
    .NWE(nwe),
    .AD(ad),
    .rd_data(module_in),
    .wr_data({module_out2,module_out}),
    .cs(cs),
    .addr_en(addr_en),
    .rd_en(rd_en),
    .wr_en(wr_en),
    .reset_n(reset)
    );



    // 初始设置
    initial begin
        // 初始化所有输入信号
        reset = 1'b1;
        nadv = 1'b1;
        nwe = 1'b1;
        noe = 1'b1;
        ad_dir =0;
        module_out = 'z;
        module_out2 = 'z;
        module_in ='z;
        ad_out = 18'bz;
        #2;

        // 释放复位
        reset = 1'b0;
        #5;
        reset = 1'b1;
        #5;// 等待一段时间

        // 开始测试
        // test_noise();
        mcu_write(0,'h1234);
        mcu_read(0,'hFF00);
        // mcu_interrupt();

        // 结束仿真
        #10 finsh =1;
    end

  
    // 写操作测试
    task mcu_write(input [17:0] addr,input [15:0]data);
    begin
        #5;
        
        // ----------写地址------------
        // 拉低地址片选
        nadv =0;
        ad_dir =1;//开始写
        ad_out = addr;// 写入地址
        #5;
        

        // 拉低NWE
        nwe =0;
        nadv =1;
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
        nwe =1;
        // 保持时间
        #3;
        ad_dir =0;
        $display("---------->[data]:%h",module_in);
        #8;
 
    end
    endtask

    task mcu_read(input [17:0] addr,input [15:0]module_data);
    begin
        #5;
        
        // ----------写地址------------
        nadv =0;// 先拉低地址片选
        ad_dir =1;//开始写
        ad_out = addr;// 写入地址
        #6;
        
        // 拉高地址片选
        nadv =1;// 此时应该拉低NWE
        // 保持时间
        #4;
        ad_dir =0;
        module_out = module_data;
        module_out2 = ~module_data;
        #5;


        // ----------读数据------------
        // 拉低NOE
        noe =0;
        #8;

        noe =1;
        #1;
        $display("---------->[data]:%h",ad_in);

        // ----------读取结束-----------
        #8;
        

    end
    endtask

   

    // 


endmodule