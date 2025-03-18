`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_AutoCorr;

// =========================================时钟周期定义======================================
parameter                           CLK_PERIOD                = 1    ;  // 10ns时钟周期
parameter                           HALF_CLK_PERIOD           = 0.5;
parameter                           HALF_ADC_CLK_MULT         = 10; // ADC_CLK与CLK相差的倍数的一半
logic clk;
logic adc_clk;
logic finsh;
integer count;
initial begin
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
task apply_signal(real input_mv, int cycles);
    repeat(cycles) @(negedge adc_clk)
        adc_data = mv2adc(input_mv * dut.GAIN_MAP[dut.current_gain_idx]);
endtask
// =========================================时钟周期定义======================================
logic rst_n;
// 信号定义


// 参数定义
parameter DATA_WIDTH = 12;
parameter AVG_WINDOW = 1024; // 必须为2的幂次

// 信号声明
reg stable;
reg signed[DATA_WIDTH-1:0] data_in;
wire signed [DATA_WIDTH:0] data_out;
wire en;
reg [15:0]period;
// 实例化被测模块

AutoCorr #(
    .DATA_WIDTH = 12,  // 数据位宽
    .MAX_TAU = 256     // 最大延迟点数
)dut (
    .clk(clk),                  // 200MHz主时钟
    .adc_clk(adc_clk),              // 10MHzADC时钟,在下降沿处更新data_in数据
    .en(en),                   // 高电平说明去直流数据有效，连接至去直流模块 DC_Removal.en
    .reg(data_in), // 来自去直流模块的数据
    .period(period),     // 检测周期
    .stable(stable)  // 高电平为稳定
);

// ===================初始设置==================
initial begin
    rst_n = 1'b1;
    // 初始化所有输入信号
    data_in = 12'b1000;
    stable =0;
    // 释放复位
    rst_n = 1'b0;#5;
    rst_n = 1'b1;#5;


    // 开始测试
    stable =1;
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
    integer i;
    begin
        for (i=0; i<AVG_WINDOW; i=i+1) begin
            data_in = 500 * $sin(2 * 3.1416*i/512);
            @(negedge clk);
        end
        $display("time:%d data:%d avg:%d", count, period);

        for (i=0; i<AVG_WINDOW; i=i+1) begin
            data_in = 500 * $sin(2 * 3.1416*i/256);
            @(negedge clk);
        end
        $display("time:%d data:%d avg:%d", count, period);

        for (i=0; i<AVG_WINDOW; i=i+1) begin
            data_in = 500 * $sin(2 * 3.1416*i/400);
            @(negedge clk);
        end
        $display("time:%d data:%d avg:%d", count, period);

        for (i=0; i<AVG_WINDOW; i=i+1) begin
            data_in = 500 * $sin(2 * 3.1416*i/512);
            @(negedge clk);
        end
        $display("time:%d data:%d avg:%d", count, period);
        
        // 验证：
        // 1. 最终平均值应接近dc_offset（1500）
        // 2. 输出信号幅度应接近amplitude（500）
        
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
    // $monitor("time: %t data:%d",$time,data_out);
end

// 检测en上升沿并捕获数据
logic en_prev;
logic [DATA_WIDTH:0] captured_data;
always @(negedge clk) begin
    en_prev <= en;  // 同步寄存器
    if (!en_prev && en) begin  // 检测上升沿
        captured_data <= data_out;
        $display("time:%d data:%d avg:%d", count, data_in,dut.avg_reg);
    end
end

endmodule