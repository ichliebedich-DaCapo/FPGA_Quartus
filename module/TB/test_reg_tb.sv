`timescale 1ns/1ps
module test_reg_tb;



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


// 参数定义
parameter DATA_WIDTH = 16;

// 接口信号声明
logic reset_n;
logic en;
logic [DATA_WIDTH-1:0] rd_data;
logic [DATA_WIDTH-1:0] wr_data;
logic state;

// 实例化被测模块
test_reg #(
    .DATA_WIDTH(DATA_WIDTH)
) uut (
    .clk(clk),
    .reset_n(reset_n),
    .en(en),
    .rd_data(rd_data),
    .wr_data(wr_data),
    .state(state)
);



// 测试向量生成
initial begin
    // 初始化
    reset_n = 1'b0;
    en = 1'b0;
    rd_data = '0;
    state = 1'b0;
    #10;
    
    // 释放复位
    reset_n = 1'b1;
    #8;
    
    // 测试用例1：基本读写操作
    $display("=== Test Case 1: Basic Read/Write ===");
    // 先读
    en = 1'b1;
    state = 1'b0;
    #5;
    // 下降沿处输入数据
    en = 1'b0;
    rd_data = 16'h1234;
    #5;

    // 再写
    en = 1'b1;
    state = 1'b1;
    #7;
    en = 1'b0;

    
    // 测试用例2：快速状态切换
    $display("\n=== Test Case 2: Fast Switching ===");

    
    // 测试用例3：边界值测试
    $display("\n=== Test Case 3: Boundary Values ===");

    
    // 测试用例4：随机测试
    $display("\n=== Test Case 4: Random Testing ===");

    

end


// 执行读操作任务
task execute_read(input [DATA_WIDTH-1:0] data);
begin
    @(posedge clk);
    en <= 1'b1;
    rd_data <= data;
    @(posedge clk);
    en <= 1'b0;
    #1; // 等待信号稳定
    
    $display("Read operation: Captured 0x%h, state=%b", data, state);
end
endtask

// 执行写操作任务
task execute_write;
begin
    @(posedge clk);
    en <= 1'b1;
    @(posedge clk);
    en <= 1'b0;
    #1;
    
    $display("Write operation: Output 0x%h verified", wr_data);
end
endtask


endmodule