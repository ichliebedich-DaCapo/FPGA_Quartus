`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_divider_10;

// =========================================时钟周期定义======================================
parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
parameter                           HALF_CLK_PERIOD           = 0.5;
logic clk;
logic finsh;
integer count;
initial begin
    clk = 0; 
    finsh = 0;
    count =0;
    fork
        begin : loop_block
            forever begin
                #HALF_CLK_PERIOD clk = ~clk; // 每个周期翻转一次
                if(clk) count = count + 1;
                if (finsh == 1'b1) begin
                    disable loop_block; // 使用 disable 退出
                end
            end
        end
    join
end
// =========================================时钟周期定义======================================

// 信号定义
logic rst_n;
logic [11:0] adc_data;
logic [1:0] relay_ctrl;
logic stable;

// 实例化被测模块





// **************用于测试*****************
auto_gain_control dut (
    .adc_clk(clk),
    .rst_n(rst_n),
    .adc_data(adc_data),
    .relay_ctrl(relay_ctrl),
    .stable(stable)
);


// ===================初始设置==================
initial begin
    // 初始化所有输入信号
    rst_n = 1'b1;
    div = 0 ;

    // 释放复位
    rst_n = 1'b0;#5;
    rst_n = 1'b1;#5;


    // 开始测试
    $display("\n=== start:%d ===\n",$time);
    test_1();
    #10;
    test_2();
    #10;


    // 结束仿真 
    finsh = 1'b1;
end

  
// 测试 1
task test_1;
begin
#100;
div =1;

end
endtask

// 测试 2
task test_2;
begin

#100;
div =2;
#500;

end
endtask


// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    // $monitor("at %t",$time);
end

endmodule