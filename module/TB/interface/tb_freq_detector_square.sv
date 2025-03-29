`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_freq_detector_square;

// =========================================时钟周期定义======================================
parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
parameter                           HALF_CLK_PERIOD           = 0.5;
parameter                           HALF_ADC_CLK_MULT         = 10; // ADC_CLK与CLK相差的倍数的一半
logic clk;
logic finsh;
integer count;
initial begin
    $timeformat(-9, 0, "", 6);
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
reg signal_in;
reg [17:0] period;

// 实例化被测模块
freq_detector_square uut (
    .clk(clk),
    .rst_n(rst_n),
    .stable(stable),
    .period(period),
    .signal_in(signal_in)
);


// ===================初始设置==================
initial begin
    rst_n = 1'b1;
    // 初始化所有输入信号
    signal_in = 0;
    // 释放复位
    rst_n = 1'b0;#5;
    rst_n = 1'b1;#5;


    // 开始测试
    generate_signal(20,100);

    generate_signal(60,80);

    generate_signal(520,60);

    #10;


    // 结束仿真 
    finsh = 1'b1;
end


task generate_signal(input int half_period, input int cycles);
    begin
        $display("time:%t---------------Period:%d------------------",$time,half_period*2);
        repeat(cycles) begin
            signal_in = 0;
            repeat(half_period)begin
                @(posedge clk);
            end
            signal_in = 1;
            repeat(half_period)begin
                @(posedge clk);
            end
        end
        $display("time:%t --------done------",$time);
    end
endtask


// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    $monitor("time:%t period:%d stable:%d valid:%d cnt:%d",$time,period,stable,uut.valid,uut.stable_cnt);
end

// 检测en上升沿并捕获数据

endmodule