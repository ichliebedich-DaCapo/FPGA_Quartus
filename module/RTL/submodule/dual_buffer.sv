// 【简介】：双缓冲子模块
// 【功能】：根据稳定信号，从ADC读取数据，使用双缓冲机制。同时添加了触发机制，只在电压比较器处于上升沿时开始读取。
// 【Fmax】：257MHz
// 【note】：单片机如果想要读取数据，先读取READ_STATE_ADDR处的数据，如果为1，那么久可以读取了。
//          然后需要对READ_STATE_ADDR地址处写入1，然后读取，读取完之后，再写入0，表示读取完成。
module dual_buffer #(
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
    // ADC信号（跨时钟域）
    input  wire                  adc_clk,
    input  wire [11:0]           sync_adc_data,// 必须是同步信号，因此需要通过同步模块
    input  wire                  stable,
    input  wire                  sync_signal_in,// 接电压比较器的方波信号   必须是同步信号，因此需要通过同步模块
    // 外部模块接口
    input  wire [DATA_WIDTH-1:0] rd_data,    // 读数据
    output reg [DATA_WIDTH-1:0] wr_data     // 写数据
);

// ================== 状态机与缓冲区定义 ==================
typedef enum logic [1:0] {
    IDLE,
    SAMPLING,//准备状态
    SWITCH_BUF
} State;

State current_state;
reg [DATA_WIDTH-1:0]addr;
reg   write_buf;      // 当前写缓冲区 (0或1)
reg write_buf_copy1,write_buf_copy2;
reg  [$clog2(BUF_SIZE)-1:0] write_ptr;
(* ram_style = "block" *) reg  [11:0] buffer0 [BUF_SIZE];
(* ram_style = "block" *) reg  [11:0] buffer1 [BUF_SIZE];

reg reg_read;// 读寄存器，高电平表明单片机开始读数据了
reg reg_read_prev;

// 【读状态寄存器】，单片机可通过读操作判断是否可以读取，通过写入1表示正在读取，写入0表示读取完成
localparam READ_STATE_ADDR = 16'h4000;

// ================== 边沿检测 ==================
reg adc_clk_prev,signal_in_prev;
// 复制多份高扇出信号
reg buf_full; // 标志当前缓冲区已满

reg trigger_condition;// 触发条件
wire adc_clk_rising = (adc_clk & ~adc_clk_prev);
wire signal_in_rising = (sync_signal_in & ~signal_in_prev);// 与ADC_CLK同频的上升沿信号
wire reg_read_rising = reg_read & ~reg_read_prev;
always @(posedge clk) begin
    adc_clk_prev <= adc_clk;// adc时钟域本就由同步分频器产生，不需要额外同步
    reg_read_prev <= reg_read;
    write_buf_copy1 <= write_buf;
    write_buf_copy2 <= write_buf;
    buf_full <= (write_ptr == BUF_SIZE - 1);
    trigger_condition <=stable && signal_in_rising && !reg_read;
    signal_in_prev  <= sync_signal_in;// 仅在adc_clk保持更新方波信号，否则无法检测到触发信号
end




// ================== 主状态机 ==================
reg has_switched;// 确保切换过缓冲区
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
        write_buf     <= 0;
        // 如果对缓冲区清零会导致存储空间不够
    end else begin
        case (current_state)
            IDLE: begin
                if (trigger_condition) begin
                    current_state <= SAMPLING;
                    write_ptr  <= 0;
                end
            end

            SAMPLING: begin
                if (!stable) begin  // stable变低则终止
                    current_state <= IDLE;
                end else if (adc_clk_rising) begin
                    // 写入当前缓冲区
                    if (write_buf_copy1)
                        buffer1[write_ptr] <= sync_adc_data;
                    else
                        buffer0[write_ptr] <= sync_adc_data;
                    
                    // 递增指针并检查是否写满
                    if (buf_full) begin
                        current_state <= SWITCH_BUF;             
                    end else begin
                        write_ptr <= write_ptr + 1'b1;
                    end
                end
            end

            SWITCH_BUF:begin
                if(!reg_read)begin
                    write_buf     <= ~write_buf;  // 切换缓冲区
                    current_state <= IDLE;
                end
            end

            default: current_state <= IDLE;
        endcase
    end
end


// ================== 外部接口读写仲裁 ==================
// 增加输出寄存器级
// 【优化】：添加了这块，让时序从172MHz提升至257MHz
reg [11:0] buffer_rd_data;
reg [DATA_WIDTH-1:0] wr_data_reg;

always_ff @(posedge clk) begin
    // 第一阶段：提前选择buffer
    if(write_buf_copy2)
        buffer_rd_data <= buffer0[addr[11:0]];
    else 
        buffer_rd_data <= buffer1[addr[11:0]];
        
    // 第二阶段：拼接数据
    wr_data_reg <= {4'b0, buffer_rd_data};
end



always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        reg_read <= 1'b0;
        wr_data <= 16'hFFFF;
    end else if(en)begin
        // 地址操作
        if(addr_en)begin
            addr <= rd_data;// 锁存地址
        end
        // 读操作
        if(rd_en)begin
            // 把单片机要写入的数据存储起来，用于判断是否可以切换缓冲区
            if(addr==READ_STATE_ADDR)
                reg_read <= rd_data[0];  
        end
        // 写操作
        if(wr_en)begin
            casez(addr)
                READ_STATE_ADDR:wr_data <= {15'b0,has_switched};
                16'h0???:wr_data <= wr_data_reg;
                default:wr_data <= 16'hFFFF;
            endcase
        end
    end
end

/*
 *  仲裁
 *  @note：确保单片机不会连续读取两次相同的缓冲区。只要开始读，那么必须等到切换至少一次缓冲区后才能读。
*/
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        has_switched <= 1'b0;
    end else if(reg_read_rising)begin
        // 上升沿，表明单片机开始读取了，此时需要重置切换标志，确保下一次读取时不会不会重复
        // 上升沿，表明单片机开始读取了，此时需要重置切换标志，确保下一次读取时不会不会重复
        has_switched <= 1'b0;// 重置切换标志
    end else if(current_state == SWITCH_BUF && !reg_read)begin
        has_switched <= 1'b1;// 只要切换一次即可
    end
end

endmodule