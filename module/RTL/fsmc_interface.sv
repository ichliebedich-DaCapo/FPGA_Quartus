// 说明：
// 对于独立模块来说，cs为高电平时，要通过state判断是什么时序，然后根据时序来执行相应操作
//      读取时序：CS处于下降沿，可以读取数据
//      写入时序：直接写入数据，在cs拉低时停止输入。（其实可以不停止，不过那样并不好）
module fsmc_interface #(
    parameter ADDR_WIDTH = 18,              // 地址/数据总线位宽
    parameter DATA_WIDTH = 16,              // 数据位宽
    parameter CS_WIDTH   = 2,               // 片选地址位宽
    parameter DATA_HOLD_CYCLES = 2,         // 数据保持周期
    parameter HIGH_ADDR_CS = 2'b01,         // 高位地址片选，这里默认指的是A[17:16]
    parameter HIGH_ADDR_WIDTH = 2           // 高位地址片选所占位数
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
    output logic        state,       // 1:读 0:写。对于独立模块来说是相反的
    output logic [2**CS_WIDTH-1:0] cs
);

// 信号声明
reg prev_nadv, prev_nwe, prev_noe;
reg [DATA_HOLD_CYCLES-1:0] hold_counter;
reg output_enable;
reg prev_output_enable;  // 新增输出使能状态寄存器

// ===============一级同步链=============
logic [2:0] sync_chain; // [NADV, NWE, NOE]
always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        sync_chain <= 3'b111;  // 初始化为无效状态（对应信号高电平）
    end else begin
        sync_chain <= {NADV, NWE, NOE}; // 位拼接顺序：NADV在最高位
    end
end

// 解包同步后信号
logic synced_nadv, synced_nwe, synced_noe;
assign {synced_nadv, synced_nwe, synced_noe} = sync_chain;

// ==================延迟===================
always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        prev_nadv <= 1'b1;
        prev_nwe <= 1'b1;
        prev_noe <= 1'b1;
    end else begin
        prev_nadv <= synced_nadv;
        prev_nwe <= synced_nwe;
        prev_noe <= synced_noe;
    end
end



// 边沿检测
wire nadv_rising  = ~prev_nadv & synced_nadv;
wire nwe_rising   = ~prev_nwe  & synced_nwe;
wire noe_rising   = ~prev_noe  & synced_noe;
wire output_enable_falling = prev_output_enable & ~output_enable;  // 新增下降沿检测

// 地址锁存与状态控制
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        state <= 1'b0;
        cs <= 0;
        rd_data <= 0;
    end else begin
        
        // 地址捕获
        if (nadv_rising) begin
            rd_data <= AD[DATA_WIDTH:0];
            
            // 片选生成
            if (AD[ADDR_WIDTH-1 -:HIGH_ADDR_WIDTH] == HIGH_ADDR_CS)begin
                state <= NWE;  // 锁存NWE状态
                cs <= (1 << AD[CS_WIDTH-1:0]);
            end 
        end

        else if(~state && nwe_rising)begin
        // ===================
        // 写数据捕获
        // ===================
            rd_data <= AD[DATA_WIDTH-1:0];
            // 写操作清除片选
            cs <= 0;
        end  

        // 读操作清除片选
        else if (state && output_enable_falling)
            cs <= 0;

    end
end


// =============================================================================
// 读数据控制
// 时序说明：
//  -需要在乎地址是否正确
//  -由于正确情况下读操作的state正好为高电平，其他情况均为低电平，所以这个可以作为控制信号
// =============================================================================
logic noe_triggered;
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        output_enable <= 0;
        hold_counter <= 0;
        prev_output_enable <= 0;  // 初始化新增寄存器
        noe_triggered  <= 0;  // 新增触发标志
    end else begin
        prev_output_enable <= output_enable;  // 同步输出使能状态
        
        if (state) begin  // 读操作
            if (noe_rising) begin
                hold_counter <= DATA_HOLD_CYCLES;
                noe_triggered <= 1;         // 标记已触发
                output_enable <= 1'b1;
            end 
            else if (noe_triggered) begin
                if (hold_counter > 0) begin
                    hold_counter <= hold_counter - 1;
                    output_enable <= 1'b1; // 保持使能
                    // 计数器结束时关闭
                    if (hold_counter == 1) begin
                        output_enable <= 1'b0;
                        noe_triggered <= 0; // 清除触发标记
                    end
                end else begin
                    output_enable <= 1'b0; // 防止计数器异常
                end
            end
            // 计数器结束后关闭使能
            else begin
                if(~NOE) output_enable <= 1'b1;     // 确保初始使能
            end
        end
        else begin
            hold_counter <= 0;
            hold_counter <= 0;
            noe_triggered  <= 0;          // 复位触发标志
        end
    end
end

// 总线驱动
assign AD = output_enable ? {{(ADDR_WIDTH-DATA_WIDTH){1'b0}}, wr_data} : {ADDR_WIDTH{1'bz}};

endmodule