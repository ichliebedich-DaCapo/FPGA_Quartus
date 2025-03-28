// 【简介】：波形信息模块
// 【功能】：可供单片机读取分频系数、波形周期计数器和二级程控。且地址映射如下：
//          0：分频系数
//          1：增益控制
//          2：周期计数器_低位
//          3：周期计数器_高位
// 【Fmax】：251MHz

module wave_information #(
    parameter COUNTER_WIDTH = 18, // 不能大于2*DATA_WIDTH
    parameter DATA_WIDTH = 16,    // 输入数据位宽
    parameter BUF_SIZE   = 1024   // 缓冲区大小（深度），需要改后面的地址
)(
    // 系统信号
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  en,
    input  wire                  addr_en,
    input  wire                  rd_en,     // 读使能
    input  wire                  wr_en,     // 写使能
    input  wire [DATA_WIDTH-1:0] rd_data,    // 读数据
    output reg [DATA_WIDTH-1:0]  wr_data,     // 写数据
    // 其他模块接口
    input wire [11:0] div,    // 12位宽的话，0到4095分频
    input [1:0] gain_ctrl,// 增益控制
    input [COUNTER_WIDTH-1:0] period
);

localparam DIV_ADDR = 0;// 分频
localparam GAIN_CTRL_ADDR = 1;// 增益控制
localparam PERIOD_ADDR_LOW = 2;// 周期计数器_低位
localparam PERIOD_ADDR_HIGH = 3;// 周期计数器_高位

// 其实根据时序，不需要addr这个寄存器存储，因为单片机读时序的情况下，不会改变rd_data里的数据
reg [DATA_WIDTH-1:0]addr;
always_ff@(posedge clk) begin
    // 锁存地址
    if(addr_en)begin
        addr <= rd_data;
    end
end

always_ff@(posedge clk) begin
    // 写入数据
    if(wr_en)begin
        case(addr)
            DIV_ADDR:wr_data <= {4'b0,div};
            GAIN_CTRL_ADDR:wr_data <= {14'b0,gain_ctrl};
            PERIOD_ADDR_LOW:wr_data <= period[DATA_WIDTH-1:0];
            PERIOD_ADDR_HIGH:wr_data <={{(2*DATA_WIDTH-COUNTER_WIDTH){1'b0}},period[COUNTER_WIDTH-1:DATA_WIDTH]};
            default: wr_data <= 16'hFFFF;
        endcase
    end
end

endmodule