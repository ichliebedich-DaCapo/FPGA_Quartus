// 说明：
// 对于独立模块来说，cs为高电平时，要通过state判断是什么时序，然后根据时序来执行相应操作
//      读取时序：CS处于下降沿，可以读取数据
//      写入时序：直接写入数据，在cs拉低时停止输入。（其实可以不停止，不过那样并不好）
module fsmc_interface #(
    parameter ADDR_WIDTH = 18,              // 地址/数据总线位宽
    parameter DATA_WIDTH = 16,              // 数据位宽
    parameter CS_WIDTH   = 2,               // 片选地址位宽
    parameter DATA_HOLD_CYCLES = 2,         // 数据保持周期
    parameter HIGH_ADDR_CS = 16'b0100_0000  // 高位地址片选，也就是除去低位片选地址剩下的部分。
)(
    // ================= 物理接口 =================
    inout  [ADDR_WIDTH-1:0] AD,      // 复用地址/数据总线
    input         NADV,               // 地址有效指示（低有效）
    input         NWE,                // 写使能（低有效）
    input         NOE,                // 读使能（低有效）
    
    // ================= 系统接口 =================
    input         clk,                // 主时钟
    input         reset_n,            // 异步复位
    
    // ================= 用户接口 =================
    output logic [DATA_WIDTH-1:0] rd_data,
    input  logic [DATA_WIDTH-1:0] wr_data,
    output logic         state,       // 1:读 0:写
    output logic [2**CS_WIDTH-1:0] cs
);

// 信号声明
reg [ADDR_WIDTH-1:0] addr_latched;
reg prev_nadv, prev_nwe, prev_noe;
reg [DATA_HOLD_CYCLES-1:0] hold_counter;
reg output_enable;
reg prev_output_enable;  // 新增输出使能状态寄存器

// 边沿检测
wire nadv_rising  = ~prev_nadv & NADV;
wire nwe_rising   = ~prev_nwe  & NWE;
wire noe_rising   = ~prev_noe  & NOE;
wire output_enable_falling = prev_output_enable & ~output_enable;  // 新增下降沿检测

// 地址锁存与状态控制
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        prev_nadv <= 1'b1;
        addr_latched <= 0;
        state <= 1'b0;
        cs <= 0;
    end else begin
        prev_nadv <= NADV;
        
        // 地址捕获
        if (nadv_rising) begin
            addr_latched <= AD;
            
            // 片选生成
            if (AD[ADDR_WIDTH-1 -:16] == HIGH_ADDR_CS)begin
                state <= NWE;  // 锁存NWE状态
                cs <= (1 << AD[CS_WIDTH-1:0]);
            end else
                cs <= 0;
        end
        
        // 写操作清除片选
        else if (~state && nwe_rising)
            cs <= 0;

        // 读操作清除片选
        else if (state && output_enable_falling)
            cs <= 0;

    end
end

// =============================================================================
// 写数据捕获
// 时序说明：
//  -不需要管地址是否符合，因为不片选，那么这个数据就不会被模块使用
// =============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        rd_data <= 0;
    end else if (~state && nwe_rising) begin
        rd_data <= AD[DATA_WIDTH-1:0];
    end
end

// =============================================================================
// 读数据控制
// 时序说明：
//  -需要在乎地址是否正确
//  -由于正确情况下读操作的state正好为高电平，其他情况均为低电平，所以这个可以作为控制信号
// =============================================================================
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        prev_noe <= 1'b1;
        output_enable <= 0;
        hold_counter <= 0;
        prev_output_enable <= 0;  // 初始化新增寄存器
    end else begin
        prev_noe <= NOE;
        prev_output_enable <= output_enable;  // 同步输出使能状态
        
        if (state) begin  // 读操作
            if (noe_rising) begin
                hold_counter <= DATA_HOLD_CYCLES;
                output_enable <= 1'b1;
            end 
            else if (|hold_counter) begin
                hold_counter <= hold_counter - 1;
            end
            
            if (hold_counter == 1)
                output_enable <= 1'b0;
        end
        else begin
            output_enable <= 1'b0;
            hold_counter <= 0;
        end
    end
end

// 总线驱动
assign AD = output_enable ? {{(ADDR_WIDTH-DATA_WIDTH){1'b0}}, wr_data} : {ADDR_WIDTH{1'bz}};

// 写使能同步
always @(posedge clk) prev_nwe <= NWE;

endmodule