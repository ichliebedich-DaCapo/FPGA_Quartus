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
reg [DATA_WIDTH-1:0] adc_data;
reg signal_in;
reg rd_en;
reg wr_en;
reg addr_en;
reg rd_en;
reg wr_en;
reg addr_en;

// 实例化被测模块
dual_buffer uut (
    // 系统信号
    .clk(clk),
    .rst_n(rst_n),
    // ADC信号（跨时钟域）
    .adc_clk(adc_clk),
    .sync_adc_data(adc_data),
    .stable(stable),
    .sync_signal_in(signal_in),// 接电压比较器的方波信号
    // 外部模块接口
    .en(en),
    .addr_en(addr_en),
    .rd_en(rd_en),
    .wr_en(wr_en),
    .addr_en(addr_en),
    .rd_en(rd_en),
    .wr_en(wr_en),
    .rd_data(rd_data),    // 读数据
    .wr_data(wr_data)     // 写数据
);


// ===================初始设置==================
initial begin
    rst_n = 1'b1;
    // 初始化所有输入信号
    signal_in = 0;
    en = 0;
    addr_en = 0;
    wr_en = 0;
    rd_en = 0;
    addr_en = 0;
    wr_en = 0;
    rd_en = 0;
    stable =0;
    adc_data = 0;
    rd_data = 0;

    // 释放复位
    rst_n = 1'b0;#5;
    rst_n = 1'b1;#5;

    $display("==================test:1==================");
    read_data();
    $display("==================test:2==================");
    // read_data();
    // $display("==================test:3==================");
    // read_data();
    

    #100;
    // 结束仿真 
    finsh = 1'b1;
end

initial begin
    #10;
    for (int i = 0; i < 100; i++) begin
        generate_adc(i*10);
        #10;
    end
    // 结束仿真 
    $display("=========ADC_Done==========");
    finsh = 1'b1;
end

// 生成ADC数据
task generate_adc(input [11:0] offset = 0);
begin
    // 启动采集条件
    signal_in =0;
    #10 stable = 1;
    @(posedge clk);
    signal_in = 1;
    @(posedge clk);
    
    // 生成ADC数据（简单递增模式）
    for (int i=0; i<BUF_SIZE; i++) begin
        adc_data = i[11:0]+offset;
        @(posedge adc_clk);
        $display("[%d] ADC_DATA:%d data:%d wr_buf:%d ptr:%d virtual_ptr:%d buf:%d",count,adc_data,uut.sync_adc_data,uut.write_buf_write,uut.write_ptr,uut.virtual_write_ptr,uut.buffer[uut.virtual_write_ptr]);
    end
end
endtask
    
// 读取数据
task read_data();
begin
    wait(uut.has_switched)
    $display("%d--> ready to read data : ptr:%d",count,uut.write_ptr);
    fsmc_read(READ_STATE_ADDR);// 获取状态
    fsmc_write(READ_STATE_ADDR,1);// 写入1，表示正在读取
    for (int i=0; i<BUF_SIZE; i++) begin
        fsmc_read(i);
    end
    fsmc_write(READ_STATE_ADDR,0);// 写入0，表示读取完成
end
endtask


// 模拟FSMC读取操作
// 向子模块读取数据，那么子模块就是写入时序
// 向子模块读取数据，那么子模块就是写入时序
task fsmc_read(input [15:0] addr);
begin
    @(posedge clk);
    @(posedge clk);
    en = 1;
    rd_data = addr; // 地址作为输入
    @(posedge clk);
    addr_en = 1;
    @(posedge clk);
    addr_en = 0;
    #6;
    // -----读取数据-----
    wr_en = 1;
    #5;
    // 在wr持续过程中读出数据
    if(addr == READ_STATE_ADDR)begin
        $display("data:%d switch:%d",wr_data,uut.has_switched);
    end else begin
        $display("[%0d]: -> %0d  buf0:%d  buf1:%d  ptr:%d wr_buf:%d rd_buf:%d", addr, wr_data,uut.buffer[addr],uut.buffer[addr+1024],uut.write_ptr,uut.write_buf_write,uut.write_buf_read);
    end
    #3;
    wr_en = 0;
    en =0;
    @(posedge clk);
end
endtask

// 向子模块写入数据,字模块就是读取时序
// 向子模块写入数据,字模块就是读取时序
task fsmc_write(input [15:0] addr,input [15:0] data);
begin
    @(posedge clk);
    @(posedge clk);
    en = 1;
    rd_data = addr; // 地址作为输入
    @(posedge clk);
    addr_en = 1;
    @(posedge clk);
    addr_en = 0;
    #6;
    // -----写入数据供模块读取-----
    rd_data = data;
    @(posedge clk);
    @(posedge clk);
    rd_en = 1;
    @(posedge clk);
    rd_en = 0;
    en = 0;
    @(posedge clk);
    @(posedge clk);
    $display("[W] time:%t reg_read:%d",$time,uut.reg_read);
end
endtask



// ==============================监测内部变量===============================
initial begin
    // $display("Stored Data = %h", uut.test_reg.stored_data); // 层次化路径
    $monitor("time:%t switch:%d  buf:%d reg_read:%d",$time,uut.has_switched,uut.write_buf,uut.reg_read);
end

// 检测en上升沿并捕获数据

endmodule