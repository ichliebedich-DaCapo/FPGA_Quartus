module dual_buffer #(
    parameter DATA_WIDTH = 16,    // 数据位宽
    parameter BUF_SIZE   = 1024   // 缓冲区大小（深度）
)(
    // 系统信号
    input  wire                  clk,
    input  wire                  rst_n,
    // ADC信号（跨时钟域）
    input  wire                  adc_clk,
    input  wire [11:0]           adc_data,
    input  wire                  stable,
    input  wire                  signal_in,
    // 外部模块接口
    input  wire                  en,
    input  wire                  state,     // 0=读 1=写
    input  wire [DATA_WIDTH-1:0] rd_data,    // 读数据
    output reg [DATA_WIDTH-1:0] wr_data     // 写数据
);

// ================== 状态机与缓冲区定义 ==================
localparam IDLE     = 2'b00;
localparam SAMPLING = 2'b01;
localparam ERROR    = 2'b10;

reg  [1:0]          current_state;
reg                 write_buf;      // 当前写缓冲区 (0或1)
reg  [$clog2(BUF_SIZE)-1:0] write_ptr;
reg  [11:0] buffer0 [0:BUF_SIZE-1];
reg  [11:0] buffer1 [0:BUF_SIZE-1];
reg is_read_ready;
reg reg_read;// 读寄存器，高电平表明单片机开始读数据了
reg reg_read_prev;

// 【读状态寄存器】，单片机可通过读操作判断是否可以读取，通过写入1表示正在读取，写入0表示读取完成
localparam READ_STATE_ADDR = 16'h4000;

// ================== 跨时钟域同步逻辑 ==================
// 同步adc_clk域的触发信号到clk域
reg  [2:0] sync_stable;
reg  [2:0] sync_signal_in;
// 检测signal_in上升沿
wire signal_rise = (sync_signal_in[2:1] == 2'b01);

// ================== 数据写入逻辑（跨时钟域处理） ==================
reg  [DATA_WIDTH-1:0] adc_data_sync;
reg [1:0] adc_clk_sync;
reg  [1:0] adc_sample_en;
wire adc_clk_rising = (adc_clk_sync[1:0] == 2'b01); // 正确边沿检测
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        adc_sample_en <= 0;
        sync_stable     <= 3'b0;
        sync_signal_in  <= 3'b0;
    end else begin
        sync_stable     <= {sync_stable[1:0], stable};
        sync_signal_in  <= {sync_signal_in[1:0], signal_in};
        // 检测adc_clk上升沿
        adc_sample_en <= {adc_sample_en[0], adc_clk};
    end
end
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
        adc_data_sync <= 12'b0;
    else if (adc_clk_rising) // 仅在adc_clk上升沿采样
        adc_data_sync <= adc_data;
end

// ================== 主状态机 ==================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
        write_buf     <= 0;
        write_ptr     <= 0;
    end else begin
        case (current_state)
            IDLE: begin
                if (sync_stable[2] && signal_rise && !reg_read) begin
                    current_state <= SAMPLING;
                    write_ptr     <= 0;
                end
            end

            SAMPLING: begin
                if (!sync_stable[2]) begin  // stable变低则终止
                    current_state <= ERROR;
                end else if (write_ptr == BUF_SIZE-1) begin
                    current_state <= IDLE;
                    write_buf     <= ~write_buf;  // 切换缓冲区
                    write_ptr     <= 0;
                end else if(adc_clk_rising) begin
                    write_ptr <= write_ptr + 1;
                    // 写入当前缓冲区
                    if (write_buf == 0)
                        buffer0[write_ptr] <= adc_data_sync;
                    else
                        buffer1[write_ptr] <= adc_data_sync;
                end
            end

            ERROR: begin
                if (sync_stable[2]) 
                    current_state <= IDLE;
            end
        endcase
    end
end



// ================== 外部接口读写仲裁 ==================
reg en_prev;
wire en_rising = en & !en_prev;
wire en_falling = !en & en_prev;
wire reg_read_falling = reg_read_prev & ~reg_read;// 表明单片机读取完了

typedef enum logic [2:0] {
    FSMC_IDLE,
    FSMC_JUDGE,//准备状态
    FSMC_READ,
    FSMC_WRITE
} FSMC_State;
FSMC_State fsmc_state;
reg [DATA_WIDTH-1:0]addr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        en_prev  <= 0;
        reg_read <= 0;
        reg_read_prev <= 0;
    end else begin
        en_prev <= en;
        case (fsmc_state)
            FSMC_IDLE: begin
                if(en_rising)begin
                    fsmc_state <= FSMC_JUDGE;
                    addr <= rd_data;// 锁存地址
                end
            end
            FSMC_JUDGE: begin
                if(state)begin
                    fsmc_state <= FSMC_WRITE;
                end else begin
                    fsmc_state <= FSMC_READ;
                end
            end
            // 本模块读，单片机写
            FSMC_READ: begin
                if(en_falling)begin
                    fsmc_state <= FSMC_IDLE;
                    case (addr)
                        READ_STATE_ADDR: begin
                            reg_read_prev <= reg_read;
                            reg_read <= rd_data[0]; 
                        end
                    endcase
                end
            end
            // 本模块写，单片机读
            FSMC_WRITE: begin
                if(~en)begin
                    fsmc_state <= FSMC_IDLE;
                end

                if(addr < BUF_SIZE)begin
                    if (write_buf == 0)
                        wr_data <= {4'b0, buffer0[addr]}; // 填充高4位为0
                    else
                        wr_data <= {4'b0, buffer1[addr]}; // 填充高4位为0
                end else begin
                    case(addr)
                        READ_STATE_ADDR:begin
                            wr_data <= {15'b0,is_read_ready};
                        end
                        default:begin
                            wr_data <= 16'hFFFF;// Dummy Data
                        end
                    endcase
                end
            end
        endcase
        
    end
end

// ================== 冲突处理 ==================
// 保证缓冲区切换时无读操作
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        is_read_ready <= 0;
    end else begin
        if(current_state == SAMPLING && write_ptr == BUF_SIZE-1)begin
            is_read_ready <= 1;
        end

        // 读完缓冲区后，释放读信号
        if(reg_read_falling)begin
            is_read_ready <= 0;
        end
    end
end

endmodule