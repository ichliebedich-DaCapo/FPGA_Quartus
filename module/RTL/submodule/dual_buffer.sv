module dual_buffer #(
    parameter DATA_WIDTH = 8,    // 数据位宽
    parameter BUF_SIZE   = 1024   // 缓冲区大小（深度）
)(
    // 系统信号
    input  wire                  clk,
    input  wire                  rst_n,
    // ADC信号（跨时钟域）
    input  wire                  adc_clk,
    input  wire [DATA_WIDTH-1:0] adc_data,
    input  wire                  stable,
    input  wire                  signal_in,
    // 外部模块接口
    input  wire                  en,
    output reg                   state,     // 0=读 1=写
    output reg  [DATA_WIDTH-1:0] rd_data,    // 读数据
    input  wire [DATA_WIDTH-1:0] wr_data     // 写数据
);

// ================== 状态机与缓冲区定义 ==================
localparam IDLE     = 2'b00;
localparam SAMPLING = 2'b01;
localparam ERROR    = 2'b10;

reg  [1:0]          current_state;
reg  [1:0]          buf_status;     // 缓冲区状态: [buf1_ready, buf0_ready]
reg                 write_buf;      // 当前写缓冲区 (0或1)
reg  [7:0]          write_ptr;      // 写指针（0~255）
reg  [DATA_WIDTH-1:0] buffer0 [0:BUF_SIZE-1];
reg  [DATA_WIDTH-1:0] buffer1 [0:BUF_SIZE-1];

// ================== 跨时钟域同步逻辑 ==================
// 同步adc_clk域的触发信号到clk域
reg  [2:0] sync_stable;
reg  [2:0] sync_signal_in;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sync_stable     <= 3'b0;
        sync_signal_in  <= 3'b0;
    end else begin
        sync_stable     <= {sync_stable[1:0], stable};
        sync_signal_in  <= {sync_signal_in[1:0], signal_in};
    end
end

// 检测signal_in上升沿
wire signal_rise = (sync_signal_in[2:1] == 2'b01);

// ================== 主状态机 ==================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= IDLE;
        write_buf     <= 0;
        write_ptr     <= 0;
        buf_status    <= 2'b00;
    end else begin
        case (current_state)
            IDLE: begin
                if (sync_stable[2] && signal_rise) begin
                    current_state <= SAMPLING;
                    write_ptr     <= 0;
                    buf_status    <= (write_buf == 0) ? 2'b01 : 2'b10;
                end
            end

            SAMPLING: begin
                if (!sync_stable[2]) begin  // stable变低则终止
                    current_state <= ERROR;
                    buf_status    <= 2'b00;
                end else if (write_ptr == BUF_SIZE-1) begin
                    current_state <= IDLE;
                    write_buf     <= ~write_buf;  // 切换缓冲区
                    write_ptr     <= 0;
                end else begin
                    write_ptr <= write_ptr + 1;
                end
            end

            ERROR: begin
                buf_status <= 2'b00;
                if (sync_stable[2]) 
                    current_state <= IDLE;
            end
        endcase
    end
end

// ================== 数据写入逻辑（跨时钟域处理） ==================
reg  [DATA_WIDTH-1:0] adc_data_sync;
reg  [1:0] adc_sample_en;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        adc_data_sync <= 0;
        adc_sample_en <= 0;
    end else begin
        // 检测adc_clk上升沿
        adc_sample_en <= {adc_sample_en[0], adc_clk};
        if (adc_sample_en == 2'b01)  // 上升沿采样
            adc_data_sync <= adc_data;
    end
end

// 写入当前缓冲区
always @(posedge clk) begin
    if (current_state == SAMPLING && adc_sample_en[1]) begin
        if (write_buf == 0)
            buffer0[write_ptr] <= adc_data_sync;
        else
            buffer1[write_ptr] <= adc_data_sync;
    end
end

// ================== 外部接口读写仲裁 ==================
reg  [7:0] rd_addr;
reg        rd_busy;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state    <= 0;
        rd_data  <= 0;
        rd_addr  <= 0;
        rd_busy  <= 0;
    end else begin
        // 检测en上升沿
        if (en && !state) begin
            state   <= 1;          // 标记为写操作
            rd_addr <= wr_data;    // 地址来自wr_data
        end else if (!en && state) begin
            state <= 0;
            // 读操作完成
            rd_busy <= 0;
        end

        // 读数据输出
        if (state == 0 && en) begin
            if (buf_status[0] && rd_addr < BUF_SIZE) begin
                rd_data <= buffer0[rd_addr];
                rd_busy <= 1;
            end else if (buf_status[1] && rd_addr < BUF_SIZE) begin
                rd_data <= buffer1[rd_addr];
                rd_busy <= 1;
            end
        end
    end
end

// ================== 冲突处理 ==================
// 保证缓冲区切换时无读操作
always @(posedge clk) begin
    if (current_state == SAMPLING && write_ptr == BUF_SIZE-1) begin
        if (rd_busy) begin
            // 延迟切换直到读完成
            write_ptr <= BUF_SIZE-1;  // 保持指针
        end else begin
            buf_status <= (write_buf == 0) ? 2'b10 : 2'b01;
        end
    end
end

endmodule