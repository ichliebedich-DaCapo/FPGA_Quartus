// 【简介】：FSMC接口模块
// 【功能】：把FSMC异步复用时序转为内部协议，内部协议共有cs、addr_en、rd_en、wr_en四根线。单片机先输入地址，此时cs和addr_en发出一个小脉冲，然后输出地址。接下来分为读时序和写时序：
//          读时序：rd_en发出一个小脉冲，此时可以在rd_en上升沿处读取数据
//          写时序：在wr_en为高电平时持续输入数据。
// 【note】：目前wr_en是短脉冲
// 【Fmax】：369MHz
module fsmc_interface #(
    parameter ADDR_WIDTH = 18,              // 地址/数据总线位宽
    parameter DATA_WIDTH = 16,              // 数据位宽
    parameter DATA_HOLD_CYCLES = 2,         // 数据保持周期
    parameter NUM_MODUELS = 2
)(
    // ================= 物理接口 =================
    inout  [ADDR_WIDTH-1:0] AD,      // 复用地址/数据总线
    input         NADV,               // 地址有效指示（低有效）
    input         NWE,                // 写使能（低有效）
    input         NOE,                // 读使能（低有效）
    
    // ================= 系统接口 =================
    input         clk,                // 主时钟
    input         rst_n,            // 异步复位
    
    // ================= 用户接口 =================
    output reg [DATA_WIDTH-1:0] rd_data,
    input  wire  [DATA_WIDTH-1:0] wr_data_array [NUM_MODUELS-1:0], // 数组化输入
    output reg [2**(ADDR_WIDTH-DATA_WIDTH)-1:0] cs,
    output reg                  addr_en,      // 1:读 0:写。对于独立模块来说是相反的
    output reg                  rd_en,
    output reg                  wr_en
);

// 信号声明

reg [DATA_HOLD_CYCLES-1:0] hold_counter;
reg output_enable;
reg prev_output_enable;  // 新增输出使能状态寄存器

// ========================================================================
// 一级同步链
// 说明：
//      - 不添加同步链，那么错误率高达 12%
//      - 仅仅添加一级同步链，就可以在1万次快速传输的情况下，错误率达到 0%。
// ========================================================================
logic [2:0] sync_chain; // [NADV, NWE, NOE]
logic [ADDR_WIDTH-1:0]sync_ad_data;
// 解包同步后信号
logic synced_nadv, synced_nwe, synced_noe;
assign {synced_nadv, synced_nwe, synced_noe} = sync_chain;
reg prev_nadv, prev_nwe, prev_noe;
// ==================延迟===================
reg write_finish;
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sync_ad_data <= 18'bz;
        sync_chain <= 3'b111;  // 初始化为无效状态（对应信号高电平）
        prev_nadv <= 1'b1;
        prev_nwe <= 1'b1;
        prev_noe <= 1'b1;
        prev_output_enable <= 1'b0;
        write_finish <= 1'b0;
    end else begin
        sync_ad_data <= AD;
        sync_chain <= {NADV, NWE, NOE}; // 位拼接顺序：NADV在最高位
        prev_nadv <= synced_nadv;
        prev_nwe <= synced_nwe;
        prev_noe <= synced_noe;
        prev_output_enable <= output_enable;  // 同步输出使能状态
        write_finish <=( hold_counter >= DATA_HOLD_CYCLES - '1);
    end
end

reg wr_state;// 读写状态
reg cs_reg;
// 边沿检测
wire nadv_rising  = ~prev_nadv & synced_nadv;
wire nwe_rising   = ~prev_nwe  & synced_nwe;
wire noe_rising   = ~prev_noe  & synced_noe;
wire noe_falling  = prev_noe  & ~synced_noe;

// 地址锁存与状态控制
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cs <= 0;
        cs_reg <= 0;
        rd_en <= 1'b0;
        addr_en <= 1'b0;
        rd_data = 0;
    end else begin
        // 地址捕获
        if (nadv_rising) begin
            {cs_reg, rd_data}<=AD;
            cs <= 1<<AD[ADDR_WIDTH-1'b1:DATA_WIDTH];
            addr_en <= 1'b1;
            wr_state <= synced_nwe; 
        end else if(nwe_rising)begin
        // ===================
        // 单片机写数据捕获
        // ===================
            rd_data <= sync_ad_data[DATA_WIDTH-1:0];  
            rd_en <= 1'b1;
        end else if (rd_en) begin
            // 读操作清除片选
            cs <= 0;
            rd_en <= 1'b0;
        end else if (write_finish)begin
            // 写操作清除片选
            cs <= 0;
        end else begin
            addr_en <= 1'b0;
        end
    end
end


// =============================================================================
// 读数据控制
// 时序说明：
//  -需要在乎地址是否正确
//  -由于正确情况下读操作的state正好为高电平，其他情况均为低电平，所以这个可以作为控制信号
// =============================================================================
logic noe_triggered;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        output_enable <= 0;
        hold_counter <= 0;
        noe_triggered  <= 0;  // 新增触发标志
        wr_en <=0;
    end else if (wr_state) begin  // 读操作
        if (noe_rising) begin
            noe_triggered <= 1'b1;         // 标记已触发
            hold_counter <= 0;
        end else if (noe_triggered) begin
            hold_counter <= hold_counter + 1'b1;  // 默认递增
            if (write_finish) begin
                output_enable <= 1'b0;
                wr_en         <= 1'b0;
                noe_triggered <= 1'b0;
                hold_counter  <= 0;  // 复位计数器
            end
        end else if(noe_falling) begin
            // 确保初始使能
            output_enable <= 1'b1;
            wr_en <= 1'b1;// 模块写操作使能
        end
    end
end

// 总线驱动
assign AD = output_enable ? {{(ADDR_WIDTH-DATA_WIDTH){1'bz}}, wr_data_array[cs_reg]} : {ADDR_WIDTH{1'bz}};

endmodule