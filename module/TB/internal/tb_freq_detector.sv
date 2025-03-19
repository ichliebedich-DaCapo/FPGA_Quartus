`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_freq_detector;

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
logic rst_n;
// 信号定义


// 参数定义
parameter DATA_WIDTH = 12;
parameter AVG_WINDOW = 1024; // 必须为2的幂次

// 信号声明
reg stable;
reg signed[DATA_WIDTH-1:0] data_in;
reg  [DATA_WIDTH-1:0] data_out;


// 实例化被测模块
freq_detector #(
    .STABLE_CYCLES(3)
)dut (
    .adc_clk(clk),
    .rst_n(rst_n),
    .stable(stable),
    .data_in(data_in),
    .period(data_out)
);


// ===================初始设置==================
initial begin
    rst_n = 1'b1;
    // 初始化所有输入信号
    data_in = 12'b10000;
    // 释放复位
    rst_n = 1'b0;#5;
    rst_n = 1'b1;#5;


    // 开始测试
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
    integer i;
    begin
        // 1024
        for (i=0; i<AVG_WINDOW*4; i=i+1) begin
            data_in =  500 * $sin(2 * 3.1416*i/1024);
            @(posedge clk);
        end
        $display("1024---> time:%d data:%d ", count, data_out);

        for (i=0; i<AVG_WINDOW*3; i=i+1) begin
            data_in =  500 * $sin(2 * 3.1416*i/512);
            @(posedge clk);
        end
        $display("512---> time:%d data:%d", count, data_out);

        for (i=0; i<AVG_WINDOW*5; i=i+1) begin
            data_in =  500 * $sin(2 * 3.1416*i/400);
            @(posedge clk);
        end
        $display("400---> time:%d data:%d", count, data_out);

        for (i=0; i<AVG_WINDOW; i=i+1) begin
            data_in =  500 * $sin(2 * 3.1416*i/256);
            @(posedge clk);
        end
        $display("256---> time:%d data:%d", count, data_out);
        
    end

end
endtask

// 测试 2
task test_2;
begin

end
endtask


// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    $monitor("time: %t data:%d  stable:%d",$time,data_out,stable);
end

// 检测en上升沿并捕获数据

endmodule