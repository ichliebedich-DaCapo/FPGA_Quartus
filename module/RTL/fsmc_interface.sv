// 说明：
// 1，为了让其他模块可以在cs上升沿时读取地址，我把解码过程延迟了一个周期
// 2,为了让其他模块可以在cs下降沿时读取数据，我把写过程延迟了一个周期


// `define DEBUG

module fsmc_interface(
    // 接口端口定义
    inout [17:0] AD,                // 地址数据复用线
    input NADV,                     // 地址有效信号
    input NWE,                      // 写有效信号
    input NOE,                      // 读有效信号
    input reset,                    // 复位信号
    input clk,                      // 时钟信号
    input  reg[15:0] module_out,      // 数据输出
    output reg[15:0] module_in,  // 地址数据输入
    output reg[2:0] cs_addr_latch,  // 片选地址缓存
    input reg cs_state,             // 片选状态，0：表示片选无效，1：表示片选有效
    output reg en_cs                //使能片选

    // 为了调试
`ifdef DEBUG
    ,output [3:0] debug_state
`endif
);

     // -----将AD设置为三态输出------
    logic ad_dir;
    reg [17:0] ad_out;
    wire [17:0] ad_in;
    assign ad_in = AD;
    assign AD = ad_dir ? ad_out : 18'bz;



    // ------------------同步化异步输入信号----------------
    logic nadv_sync,nadv_sync_d1;
    logic nwe_sync,nwe_sync_d1;
    logic noe_sync,noe_sync_d1;

    always_ff @(posedge clk or negedge reset) begin
        if (!reset)begin
            nadv_sync<=0;
            nwe_sync<=0;
            noe_sync<=0;
            nadv_sync_d1<=0;
            nwe_sync_d1<=0;
            noe_sync_d1<=0;
        end else begin
            // 同步化
            nadv_sync <= NADV;
            nwe_sync <= NWE;
            noe_sync <= NOE;
            // 下一级延迟
            nadv_sync_d1 <= nadv_sync;
            nwe_sync_d1 <= nwe_sync;
            noe_sync_d1 <= noe_sync;
        end
    end



	// ----------------地址和数据捕获-----------------
	logic ready_to_read_data; // 准备读取数据AD的数据
	logic ready_to_read_addr; // 准备读取地址
	logic addr_capture, data_capture; // 地址和数据捕获信号
	logic noe_posedge_capture, noe_negedge_capture; // noe的时钟沿

	// 提前计算边缘检测信号，以减少组合逻辑延迟
	logic pre_addr_capture, pre_data_capture;
	logic pre_noe_posedge_capture, pre_noe_negedge_capture;

	always_comb begin
		pre_addr_capture = ~nadv_sync_d1 & nadv_sync;
		pre_data_capture = ~nwe_sync_d1 & nwe_sync;
		pre_noe_posedge_capture = ~noe_sync_d1 & noe_sync;
		pre_noe_negedge_capture = noe_sync_d1 & ~noe_sync;
	end

	always_ff @(posedge clk or negedge reset) begin
		if (!reset) begin
			ready_to_read_addr <= 0;
			ready_to_read_data <= 0;
			addr_capture <= 0;
			data_capture <= 0;
			noe_posedge_capture <= 0;
			noe_negedge_capture <= 0;
		end else begin
			// 上升沿处捕获地址或数据
			addr_capture <= pre_addr_capture;
			data_capture <= pre_data_capture;
			noe_posedge_capture <= pre_noe_posedge_capture;
			noe_negedge_capture <= pre_noe_negedge_capture;

			if (addr_capture || data_capture) begin
				module_in <= ad_in[15:0];
				if (addr_capture) begin
					cs_addr_latch <= ad_in[17:15]; // 片选地址捕获
					ready_to_read_addr <= 1;
					ready_to_read_data <= 0;
				end else if (data_capture) begin
					ready_to_read_data <= 1;
					ready_to_read_addr <= 0;
				end
			end else begin
				ready_to_read_addr <= 0;
				ready_to_read_data <= 0;
			end
		end
	end

	// ------------------写入控制------------------
	logic write_trigger;
	logic write_enable;

	always_comb begin
		write_trigger = noe_negedge_capture & cs_state;
	end

	always_ff @(posedge clk or negedge reset) begin
		if (!reset) begin
			en_cs <= '0;
			write_enable <= 0;
			ad_dir <= 0;
		end else begin
			// noe的下降沿触发时，如果en_cs有效则写入
			if (write_trigger) begin
				write_enable <= 1;
			end else if (~noe_sync) begin
				write_enable <= 0;
			end
			
			// 输出
			if (write_enable) begin
				ad_dir <= 1;
				ad_out[15:0] <= module_out;
			end else begin
				ad_dir <= 0;
			end

			// 简化片选逻辑
			if (ready_to_read_addr) begin
				en_cs <= '1;
			end else if (ready_to_read_data | noe_posedge_capture) begin
				en_cs <= '0;
			end
		end
	end



`ifdef DEBUG
    assign debug_state = write_enable;
    
`endif

endmodule