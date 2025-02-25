// `define DEBUG
module tb_test;

// =========================================时钟周期定义======================================
parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
parameter                           HALF_CLK_PERIOD           = 0.5;
logic clk;
integer count;
// 时钟生成
initial begin
    clk = 0; 
    // forever #HALF_CLK_PERIOD clk = ~clk;                        // 每个周期翻转一次
    for (count = 0; count < 100; count = count + 1) begin
        #HALF_CLK_PERIOD clk = ~clk; // 每个周期翻转一次
    end
end
// =========================================时钟周期定义======================================

// 信号定义
logic reset;
logic nadv;                                             // MCU ----> 地址有效信号，低电平有效
logic nwe;                                              // MCU ----> 写有效信号，低电平有效
logic noe;                                              // MCU ----> 读有效信号，低电平有效

// 定义线
logic ad_dir;
wire  [17:0] ad;    
wire [17:0]  ad_in;                                   // 内部信号，用于控制 ad
logic [17:0]  ad_out;
assign ad_in =ad;
assign ad = ad_dir ?ad_out : 18'bz;

// **************用于测试*****************
// 被测模块实例化
test uut(
    .clk(clk),
    .reset_n(reset),
    .NADV(nadv),
    .NWE(nwe),
    .NOE(noe),
    .AD(ad)
);

// 初始设置
initial begin
    // 初始化所有输入信号
    reset = 1'b1;
    nadv = 1'b1;
    nwe = 1'b1;
    noe = 1'b1;
    ad_dir =0;
    ad_out = 18'bz;
    #2;

    // 释放复位
    reset = 1'b0;#5;
    reset = 1'b1;#5;

    // 开始测试
    $display("\n=== Test Case 1: Basic Read/Write ===");
    test_write();
    #10;
    test_read();
    #10;


end

  
// 写操作测试
task test_write;
begin
    // ----------写地址------------
    // 拉低地址片选
    nadv =0;
    ad_dir =1;//开始写
    ad_out = 18'b01_0000_0000;// 写入地址
    #5;

    // 拉低NWE
    nwe =0;nadv =1;#3;

    // 地址保持时间
    #1;
    ad_dir =0;
    #2;

    // ----------写数据------------
    // 写入数据
    ad_dir =1;
    ad_out = 18'h0F0F;
    #10;

    //  写入结束
    nwe =1;#3;
    ad_dir =0;
    #8;

end
endtask

task test_read;
begin
    // ----------写地址------------
    nadv =0;// 先拉低地址片选
    ad_dir =1;//开始写
    ad_out = 18'b01_0000_0000;// 写入地址
    #6;
    
    // 拉高地址片选
    nadv =1;#4;
    ad_dir =0;#5;

    // ----------读数据------------
    // 拉低NOE
    noe =0;#8;

    // noe上升沿处读取数据
    noe =1;#1;
    $display("---------->[data]:%h",ad_in);

    // ----------读取结束-----------
    #8;
    

end
endtask


// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    $monitor("cs=%b state=%b wr_data=%h Data=%h at %t", uut.cs,uut.state, uut.wr_data,uut.test_reg.stored_data,$time);
end

endmodule