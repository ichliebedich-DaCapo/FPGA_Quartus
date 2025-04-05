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
// 输入峰峰值
task apply_signal(real input_mv, int cycles);
    input_mv_reg = input_mv;
    $display("time:%t -------------------adc:%d-----------------",$time,input_mv);
    for(int i =0;i<cycles;i++)begin
         @(posedge adc_clk)adc_data = mv2adc(input_mv/2.0*($sin(2*3.14*i/512)+1));
    end
endtask
// 等待档位
task wait_gain(real input_mv,reg [1:0]target_gain);
    input_mv_reg = input_mv;
    $display("time:%t ----------------adc:%d gain:%d---------------",$time,input_mv,target_gain);
    for(int i =0;i<16'hFFFF;i++)begin
         @(posedge adc_clk)adc_data = mv2adc(input_mv/2.0*($sin(2*3.14*i/512)+1));
         if(dut.gain_ctrl==target_gain) break;
    end
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

// 应正常 00
apply_signal(1800,512*6);
// 增益应调高 01
wait_gain(600,1);
// 增益应调高 10
wait_gain(600,2);
// 应平稳 10
apply_signal(1600, 512*6); // 800mV输入
// 应提高 11
wait_gain(600,3);
// 应降低 10
wait_gain(1900,2);
// 应立即降低
apply_signal(1400, 512*6);
apply_signal(1980, 256);
// 应稳定
apply_signal(1200, 512*6);
apply_signal(1400, 512*6);
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
    $monitor("time: %t peak:%d gain:%d stable_cnt:%d stable:%d",$time,dut.peak_value,gain_ctrl,dut.stable_counter,dut.stable);
end

endmodule