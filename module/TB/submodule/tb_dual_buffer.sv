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
    for (int i=0; i<BUF_SIZE; i++) begin
        adc_data = i[11:0]+5;
        @(posedge adc_clk);
    end

    signal_in = 0;
    #10;
    @(posedge adc_clk);
    signal_in = 1;

    for (int i=0; i<BUF_SIZE-512; i++) begin
        adc_data = i[11:0]+5;
        @(posedge adc_clk);
    end

    fsmc_write(READ_STATE_ADDR,1);
    for (int i=0; i<BUF_SIZE; i++) begin
        fsmc_read(i);
    end
    fsmc_write(READ_STATE_ADDR,0);

    fsmc_read(READ_STATE_ADDR);
    #10;

    
    #10;
    fsmc_read(READ_STATE_ADDR);




    #100;


    // 结束仿真 
    finsh = 1'b1;
end




// 模拟FSMC读取操作
task fsmc_read(input [15:0] addr);
begin
    #5;
    en = 1;
    state = 1;      // 读模式
    rd_data = addr; // 地址作为输入
    #10;
    en =0;

    $display("[Addr]:%0d -> %0d  buf0:%d  buf1:%d  ptr:%d buf:%d", addr, wr_data,uut.buffer0[addr],uut.buffer1[addr],uut.write_ptr,uut.write_buf);
end
endtask

task fsmc_write(input [15:0] addr,input [15:0] data);
begin
    #5;
    en = 1;
    state = 0;      // 写模式
    rd_data = addr; // 地址作为输入
    #5;
    rd_data = data;
    #5;
    en = 0;
    #5;
    $display("reg_read:%d",uut.reg_read);
    // $display("[Addr]:%0d <- %0d", addr, data);
end
endtask



// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    $monitor("time:%t ready:%d  buf:%d",$time,uut.is_read_ready,uut.write_buf);
end

// 检测en上升沿并捕获数据

endmodule