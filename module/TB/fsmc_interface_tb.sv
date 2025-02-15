// `define DEBUG


module fsmc_interface_tb;

    // 时钟周期定义
    parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
    parameter                           HALF_CLK_PERIOD           = 0.5;

    // 信号定义
    logic clk;                                              // 时钟信号
    logic reset;
    logic nadv;                                             // MCU ----> 地址有效信号，低电平有效
    logic nwe;                                              // MCU ----> 写有效信号，低电平有效
    logic noe;                                              // MCU ----> 读有效信号，低电平有效
                                        // MCU <---> 地址和数据复用线 (AD17-AD0)
    logic [15:0]  module_out;                          // 内部信号，用于控制 module_ad
    logic [15:0]  module_in;


    logic [3:0]cs;

    // 定义线
    logic ad_dir;
    wire  [17:0] ad;    
    wire [17:0]  ad_in;                                   // 内部信号，用于控制 ad
    logic [17:0]  ad_out;


    assign ad_in =ad;
    assign ad = ad_dir ?ad_out : 18'bz;

    // **************用于测试*****************
`ifdef DEBUG
    logic [3:0] debug_state; // 用于显示状态
    // logic [2:0] debug_next_state;
`endif

    // 被测模块实例化
    fsmc_interface uut (
    .clk(clk),
    .NADV(nadv),
    .NOE(noe),
    .NWE(nwe),
    .AD(ad),
    .module_in(module_in),
    .module_out(module_out),
    .cs(cs),
    .reset(reset)

    // // 用于测试
`ifdef DEBUG
    ,.debug_state(debug_state)
`endif 
    );

    integer count;
    // 时钟生成
    initial begin
        clk = 0;
        
        // forever #HALF_CLK_PERIOD clk = ~clk;                        // 每个周期翻转一次
        for (count = 0; count < 100; count = count + 1) begin
            #HALF_CLK_PERIOD clk = ~clk; // 每个周期翻转一次
        end
    end

    // 初始设置
    initial begin
        // 初始化所有输入信号
        reset = 1'b1;
        nadv = 1'b1;
        nwe = 1'b1;
        noe = 1'b1;
        ad_dir =0;
        #2;

        // 释放复位
        reset = 1'b0;
        #5;
        reset = 1'b1;
        #5;// 等待一段时间

        // 开始测试
        // test_noise();
        test_write();
        test_read();
        // test_interrupt();

        // 结束仿真
        // $stop;
    end

  
    // 写操作测试
    task test_write;
    begin
        #5;
        
        // ----------写地址------------
        // 拉低地址片选
        nadv =0;
        ad_dir =1;//开始写
        ad_out = 18'h080000;// 写入地址
        #5;
        

        // 拉低NWE
        nwe =0;
        nadv =1;
        #3;

        // 地址保持时间
        #1;
        ad_dir =0;
        #3;



        // ----------写数据------------
        // 写入数据
        ad_dir =1;
        ad_out = 18'h0F0F;
        #10;

        //  写入结束
        nwe =1;
        // 保持时间
        #3;
        ad_dir =0;

        #8;

       
    end
    endtask

    task test_read;
    begin
        #5;
        
        // ----------写地址------------
        nadv =0;// 先拉低地址片选
        ad_dir =1;//开始写
        ad_out = 18'h0001;// 写入地址
        #6;
        
        // 拉高地址片选
        nadv =1;// 此时应该拉低NWE
        // 保持时间
        #4;
        ad_dir =0;
        module_out = 16'h2321;
        #5;


        // ----------读数据------------
        // 拉低NOE
        noe =0;
        #8;

        noe =1;
        $display("---------->[data]:%h",ad_in);

        // ----------读取结束-----------
        #8;
        

    end
    endtask

   

    // 


endmodule