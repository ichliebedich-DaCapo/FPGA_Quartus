`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_fixed_to_float;

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

parameter FIXED_WIDTH = 12;
parameter EXP_WIDTH = 8;
parameter MANT_WIDTH = 23;

reg rst_n;
reg en;
reg [FIXED_WIDTH-1:0] a;
wire [EXP_WIDTH+MANT_WIDTH:0] q;

    // 实例化被测模块
    fixed_to_float uut (
        .clk(clk),
        .rst_n(rst_n),
        .en(en),
        .a(a),
        .q(q)
    );


// ===================初始设置==================
initial begin
    // 初始化
    rst_n = 0;
    a = 0;
    #100;
    rst_n = 1;

    // 开始测试
    // 测试用例1：0值
    test_case(12'h000, 32'h00000000);

    // 测试用例2：+1.0
    test_case(12'h001, 32'h3F800000); 

    // 测试用例3：-2048
    test_case(12'h800, 32'hC5000000);

    // 测试用例4：+2047
    test_case(12'h7FF, 32'h44FFE000);

    #100;

    // 结束仿真 
    finsh = 1'b1;
end

  
// 自动化校验任务
task test_case;
    input [FIXED_WIDTH-1:0] a_in;
    input [31:0] expected;
    begin
        a = a_in;
        #30; // 等待流水线延迟（3个时钟周期）
        if (q !== expected) begin
            $display("[ERROR] In:%h Out:%h E:%h", a_in, q, expected);
        end else begin
            $display("[PASS] In:%h Out:%h", a_in, q);
        end
        #10;
    end
endtask


// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    // $monitor("time: %t data:%d",$time,data_out);
end



endmodule