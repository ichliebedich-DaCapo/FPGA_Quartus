`timescale 1ns/1ps  // 时间单位=1ns，时间精度=1ps   锁相环模块添加这个，所以这里也必须添加
module tb_dual_buffer;

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


// =========================================时钟周期定义======================================
logic rst_n;
// 信号定义


// 参数定义
parameter DATA_WIDTH = 12;
localparam BUF_SIZE = 1024;
localparam READ_STATE_ADDR = 16'h4000;
// 信号声明
reg stable;
reg en;
reg [15:0] rd_data;
reg [15:0] wr_data;
reg state;
reg [DATA_WIDTH-1:0] adc_data;
reg signal_in;

// 实例化被测模块
dual_buffer uut (
    // 系统信号
    .clk(clk),
    .rst_n(rst_n),
    // ADC信号（跨时钟域）
    .adc_clk(adc_clk),
    .adc_data(adc_data),
    .stable(stable),
    .signal_in(signal_in),// 接电压比较器的方波信号
    // 外部模块接口
    .en(en),
    .state(state),     // 0=读 1=写
    .rd_data(rd_data),    // 读数据
    .wr_data(wr_data)     // 写数据
);


// ===================初始设置==================
initial begin
    rst_n = 1'b1;
    // 初始化所有输入信号
    signal_in = 0;
    en = 0;
    stable =0;
    state = 0;
    adc_data = 0;

    // 释放复位
    rst_n = 1'b0;#5;
    rst_n = 1'b1;#5;

    // 启动采集条件
    #10 stable = 1;
    @(posedge adc_clk);
    signal_in = 1;
    
    // 生成ADC数据（简单递增模式）
    for (int i=0; i<BUF_SIZE*2; i++) begin
        @(posedge adc_clk);
        adc_data = i[11:0];
    end

    fsmc_read(READ_STATE_ADDR);
    #10;

    fsmc_write(READ_STATE_ADDR,1);
    #10;
    fsmc_read(READ_STATE_ADDR);


    // 测试用例1：基本写入和缓冲区切换
    // $display("=== Test Case 1: Basic Write Operation ===");
    // test_basic_write();
    
    // // 测试用例2：跨时钟域读取验证
    // $display("=== Test Case 2: Cross-domain Read Verification ===");
    // test_read_operation();
    
    // // 测试用例3：错误状态恢复测试
    // $display("=== Test Case 3: Error State Recovery ===");
    // test_error_recovery();
    
    // // 测试用例4：读写冲突测试
    // $display("=== Test Case 4: Read-Write Conflict ===");
    // test_read_write_conflict();

    #100;


    // 结束仿真 
    finsh = 1'b1;
end

  
// // 测试用例1：基本写入操作
// task test_basic_write;
// begin
//     // 启动采集条件
//     #10 stable = 1;
//     signal_in = 1;
    
//     // 生成ADC数据（简单递增模式）
//     for (int i=0; i<BUF_SIZE*2; i++) begin
//         @(posedge adc_clk);
//         adc_data = i[11:0];
//     end
//     // fork
//     //     begin
//     //         for (int i=0; i<BUF_SIZE*2; i++) begin
//     //             @(posedge adc_clk);
//     //             adc_data = i[11:0];
//     //         end
//     //     end
//     //     begin
//     //         // 等待第一个缓冲区填满
//     //         #100;
//     //         wait(uut.write_ptr == BUF_SIZE-1);
//     //         $display("Buffer 0 filled at %0t", $time);
            
//     //         // 验证缓冲区切换
//     //         wait(uut.write_buf == 1);
//     //         $display("Buffer switched to 1 at %0t", $time);
//     //     end
//     // join
// end
// endtask

// // 测试用例2：读取操作验证
// task test_read_operation;
// begin
//     // 读取缓冲区0
//     read_buffer(0);
    
//     // 等待下一次缓冲区切换
//     wait(uut.write_buf == 0);
    
//     // 读取缓冲区1
//     read_buffer(BUF_SIZE);
// end
// endtask

// // 测试用例3：错误状态恢复
// task test_error_recovery;
// begin
//     // 触发错误状态
//     #10 stable = 0;
//     #100 stable = 1;
    
//     // 验证状态机恢复
//     wait(uut.current_state == uut.IDLE);
//     $display("Error state recovered at %0t", $time);
// end
// endtask

// // 测试用例4：读写冲突测试
// task test_read_write_conflict;
// begin
//     // fork
//     //     begin
//     //         // 启动持续写入
//     //         stable = 1;
//     //         signal_in = 1;
//     //         repeat(100) @(posedge adc_clk) adc_data = $random;
//     //     end
//     //     begin
//     //         // 随机读取操作
//     //         repeat(20) begin
//     //             #50 read_random_address();
//     //         end
//     //     end
//     // join
// end
// endtask

// // 读取指定缓冲区
// task read_buffer(input int base_addr);
// begin
//     $display("Reading buffer ......");
//     wait(uut.is_read_ready);
//     fsmc_write(READ_STATE_ADDR,1);
//     for (int i=0; i<BUF_SIZE; i++) begin
//         fsmc_read(base_addr + i);
//         // 验证数据（注意高4位补零）
//         $display("Data mismatch at addr %0h: Exp %0h, Got %0h", 
//                   i, {4'b0, i[11:0]}, wr_data);
//     end
//     fsmc_write(READ_STATE_ADDR,0);
// end
// endtask

// 模拟FSMC读取操作
task fsmc_read(input [15:0] addr);
begin
    #10;
    en = 1;
    state = 1;      // 读模式
    rd_data = addr; // 地址作为输入
    #10;
    en =0;
    $display("[Addr]:%0h -> %0h", addr, wr_data);
    // 可以从wr_data中获取数据
end
endtask

task fsmc_write(input [15:0] addr,input [15:0] data);
begin
    #10;
    en = 1;
    state = 0;      // 读模式
    rd_data = addr; // 地址作为输入
    #5;
    rd_data = data;
    #10 en = 0;
end
endtask

// // 随机地址读取
// task read_random_address;
// begin
//     automatic logic [15:0] addr = $urandom_range(0, BUF_SIZE*2);
//     fsmc_read(addr);
//     $display("Read addr %0h: %0h", addr, wr_data);
// end
// endtask

// 波形记录
// initial begin
//     $dumpfile("waveform.vcd");
//     $dumpvars(0, tb_dual_buffer);
// end


// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    $monitor("time: %t ptr:%d state:%d ready:%d",$time,uut.write_ptr,uut.fsmc_state,uut.is_read_ready);
end

// 检测en上升沿并捕获数据

endmodule