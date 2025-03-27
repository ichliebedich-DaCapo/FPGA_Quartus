// 【简介】：FSMC接口模块
// 【功能】：子模块需要满足一定时序，某位cs片选的上升沿时，此时读取数据是地址，如果此时state为低点平，那么就是单片机写时序子模块读时序，反之~。
//          单片机读时序子模块写时序：在state下降沿时可以写入数据，直到片选重回低电平。
//          单片机写时序子模块读时序：在片选下降沿时可以读取数据
// 【新想法】：内部协议“同步”时序：使用cs、addr_en、rd_en、wr_en四根线，cs表示是否片选这个模块，addr_en上升沿表示该读取地址了,rd_en表示可以读取数据了（实际是NOE下降沿）
//          wr_en表示可以写入数据了，高电平持续期间均可以写入数据
// 【Fmax】：331MHz
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
    input         reset_n,            // 异步复位
    
    // ================= 用户接口 =================
    output logic [DATA_WIDTH-1:0] rd_data,
    input  wire  [DATA_WIDTH-1:0] wr_data [NUM_MODUELS-1:0], // 数组化输入
    output logic [2**(ADDR_WIDTH-DATA_WIDTH)-1:0] cs,
    output logic                  state      // 1:读 0:写。对于独立模块来说是相反的
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
reg prev_nadv, prev_nwe, prev_noe;
// ==================延迟===================
always_ff @(posedge clk) begin
    prev_nadv <= synced_nadv;
    prev_nwe <= synced_nwe;
    prev_noe <= synced_noe;
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
    end else begin
        state <= NWE;  // 同步NWE状态
        // 地址捕获
        if (nadv_rising) begin
            rd_data <= AD[DATA_WIDTH-1:0];
            // 片选生成
            cs <= (1 << AD[ADDR_WIDTH-1 :DATA_WIDTH]);
        end else if(~state && nwe_rising)begin
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
            end else begin
                // 计数器结束后关闭使能
                if(~NOE) output_enable <= 1'b1;     // 确保初始使能
            end
        end else begin
            hold_counter <= 0;
            hold_counter <= 0;
            noe_triggered  <= 0;          // 复位触发标志
        end
    end
end

// 总线驱动
assign AD = output_enable ? {{(ADDR_WIDTH-DATA_WIDTH){1'bz}}, wr_data[cs]} : {ADDR_WIDTH{1'bz}};

endmodule