`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_auto_gain_control;

// =========================================时钟周期定义======================================
parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
parameter                           HALF_CLK_PERIOD           = 0.5;
parameter                           HALF_ADC_CLK_MULT         = 10; // ADC_CLK与CLK相差的倍数的一半
logic clk;
logic adc_clk;
logic finsh;
integer count;
initial begin
    $timeformat(-9, 0, "", 6);
    clk = 0; // @200MHz
    adc_clk = 0;// @10MHz
    finsh = 0;
    count =0;
    fork
        begin : loop_block
            forever begin
                #HALF_CLK_PERIOD clk = ~clk; // 每个周期翻转一次
                if(clk)begin
                count = count + 1;
                if(count % HALF_ADC_CLK_MULT==0) adc_clk = ~adc_clk;
                end
                if (finsh == 1'b1) begin
                    disable loop_block; // 使用 disable 退出
                end
            end
        end
    join
end

// ADC值转换函数
function logic [11:0] mv2adc(real mv);
    return (mv * 4095) / 2000; // 2V量程
endfunction

logic [11:0] adc_data;
real input_mv_reg;
task apply_signal(real input_mv, int cycles);
    input_mv_reg = input_mv;
    $display("time:%t adc:%d",$time,input_mv);
    repeat(cycles) @(posedge adc_clk)
        adc_data = mv2adc(input_mv);
endtask
// =========================================时钟周期定义======================================

// 信号定义
logic rst_n;
logic [1:0] gain_ctrl;
logic stable;



// **************用于测试*****************
auto_gain_control dut (
    .adc_clk(adc_clk),
    .rst_n(rst_n),
    .adc_data(adc_data),
    .gain_ctrl(gain_ctrl),
    .stable(stable)
);


// ===================初始设置==================
initial begin
    rst_n = 1'b1;
    // 初始化所有输入信号

    // 释放复位
    rst_n = 1'b0;#5;
    rst_n = 1'b1;#5;


    // 开始测试
    test_1();
    test_2();


    // 结束仿真 
    finsh = 1'b1;
end

  
// 测试 1
task test_1;
begin
// 初始增益
apply_signal(500,1048);// 应立即降低档位
// 测试稳定所需时间
apply_signal(600, 600); 
// 测试调低增益
apply_signal(650,600);// 应立即降低档位进入IDLE状态
apply_signal(800, 600); // 800mV输入
apply_signal(1100, 600);
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
    $monitor("time: %t adc:%d peak:%d gain:%d count:%d stable_cnt:%d stable:%d",$time,input_mv_reg,dut.peak,gain_ctrl,dut.sample_count,dut.stable_counter,dut.stable);
end

endmodule