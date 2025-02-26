module data_storage_and_process #(
    parameter DATA_WIDTH = 16,              // 寄存器数据位宽
    parameter ADC_DATA_WIDTH = 12,          // ADC数据位宽
)(
    // ================= 系统接口 =================
    input               clk,                // 主时钟 (系统时钟域)
    input               reset_n,            // 异步复位 (低有效)
    
    // ================= 用户接口 =================
    input               en,                 // 片选使能
    input  [DATA_WIDTH-1:0] rd_data,        // 地址/数据输入 (来自单片机)
    output reg [DATA_WIDTH-1:0] wr_data,    // 数据输出 (到单片机)
    input               trigger,            // 触发信号 (异步)
    input               mode,               // 模式信号 (1:高频, 0:低频)
    input               ADC_CLK,            // ADC时钟 (ADC时钟域)
    input  [ADC_DATA_WIDTH-1:0] ADC_DATA    // ADC输入数据 (ADC时钟域)
);

// ========================================================================
// 异步FIFO与跨时钟域处理
// ========================================================================
wire                  fifo_wr_en;
wire [DATA_WIDTH-1:0] fifo_din;
wire                  fifo_rd_en;
wire [DATA_WIDTH-1:0] fifo_dout;
wire                  fifo_full;
wire                  fifo_empty;

// ADC时钟域同步器
reg trigger_sync1, trigger_sync2;
always @(posedge ADC_CLK) begin
    {trigger_sync1, trigger_sync2} <= {trigger, trigger_sync1};
end

// FIFO写控制
assign fifo_wr_en = (current_state == CAPTURE_HIGH || 
                    current_state == CAPTURE_LOW) && !fifo_full;
assign fifo_din = ADC_DATA;

async_fifo u_async_fifo (
    .wrclk(ADC_CLK),
    .rdclk(clk),
    .wrreq(fifo_wr_en),
    .q(fifo_din),
    .wrfull(fifo_full),
    .rdreq(fifo_rd_en),
    .data(fifo_dout),
    .rdempty(fifo_empty)
);

// ========================================================================
// 主状态机设计
// ========================================================================
typedef enum logic [2:0] {
    IDLE,
    CAPTURE_HIGH,   // 高频模式采集
    PROCESS_HIGH,   // 高频数据处理
    CAPTURE_LOW     // 低频模式采集
} state_t;

reg [2:0] current_state, next_state;

always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) current_state <= IDLE;
    else current_state <= next_state;
end

always_comb begin
    next_state = current_state;
    case (current_state)
        IDLE: 
            if (trigger_sync2)  // 同步后的触发信号
                next_state = (mode) ? CAPTURE_HIGH : CAPTURE_LOW;
            else
                next_state = IDLE;
        
        CAPTURE_HIGH: 
            if (sample_count == 399) 
                next_state = PROCESS_HIGH;
            else 
                next_state = CAPTURE_HIGH;
        
        PROCESS_HIGH: 
            if (pipeline_done)  // 流水线处理完成
                next_state = IDLE;
            else
                next_state = PROCESS_HIGH;
        
        CAPTURE_LOW: 
            if (!mode)          // 模式改变则退出
                next_state = IDLE;
            else 
                next_state = CAPTURE_LOW;
    endcase
end

// ========================================================================
// 数据存储与计数器
// ========================================================================
reg [ADC_DATA_WIDTH-1:0] data_buffer [0:399];  // 400点存储
reg [8:0] sample_count;       // 0-399
reg [15:0] low_count;         // 低频数据计数
reg [1:0] low_state;          // 低频状态 (1/2)

// FIFO读控制
assign fifo_rd_en = (current_state == CAPTURE_HIGH) ? 
                    (sample_count < 400) : (current_state == CAPTURE_LOW);

always @(posedge clk) begin
    if (!reset_n) begin
        sample_count <= 0;
        low_count <= 0;
    end else begin
        case(current_state)
            CAPTURE_HIGH: 
                if (fifo_rd_en) begin
                    data_buffer[sample_count] <= fifo_dout;
                    sample_count <= sample_count + 1;
                end
            CAPTURE_LOW: 
                low_count <= (low_count == 16'hFFFF) ? 0 : low_count + 1;
            default: 
                sample_count <= 0;
        endcase
    end
end

// ========================================================================
// 峰峰值流水线计算（三级流水线）
// ========================================================================
// 第一级：分组比较
reg [ADC_DATA_WIDTH-1:0] stage1_max [0:79];  // 80组，每组5个数据
reg [ADC_DATA_WIDTH-1:0] stage1_min [0:79];
reg [8:0] stage1_max_idx [0:79];
reg [8:0] stage1_min_idx [0:79];
reg [7:0] stage1_cnt;

// 第二级：合并比较
reg [ADC_DATA_WIDTH-1:0] stage2_max [0:15]; // 16组，每组5个
reg [ADC_DATA_WIDTH-1:0] stage2_min [0:15];
reg [8:0] stage2_max_idx [0:15];
reg [8:0] stage2_min_idx [0:15];
reg [3:0] stage2_cnt;

// 第三级：最终比较
reg [ADC_DATA_WIDTH-1:0] final_max, final_min;
reg [8:0] final_max_idx, final_min_idx;
reg pipeline_done;

always @(posedge clk) begin
    if (!reset_n) begin
        stage1_cnt <= 0;
        stage2_cnt <= 0;
        pipeline_done <= 0;
    end else begin
        // --------------------------------------------------
        // 第一级：每周期处理5个数据（共80组）
        // --------------------------------------------------
        if (current_state == PROCESS_HIGH && stage1_cnt < 80) begin
            integer base = stage1_cnt * 5;
            // 组内比较
            {stage1_max[stage1_cnt], stage1_max_idx[stage1_cnt]} = 
                find_max(data_buffer[base], base,
                        data_buffer[base+1], base+1,
                        data_buffer[base+2], base+2,
                        data_buffer[base+3], base+3,
                        data_buffer[base+4], base+4);
            {stage1_min[stage1_cnt], stage1_min_idx[stage1_cnt]} = 
                find_min(data_buffer[base], base,
                        data_buffer[base+1], base+1,
                        data_buffer[base+2], base+2,
                        data_buffer[base+3], base+3,
                        data_buffer[base+4], base+4);
            stage1_cnt <= stage1_cnt + 1;
        end

        // --------------------------------------------------
        // 第二级：每周期处理5组（共16组）
        // --------------------------------------------------
        if (stage1_cnt == 80 && stage2_cnt < 16) begin
            integer base = stage2_cnt * 5;
            {stage2_max[stage2_cnt], stage2_max_idx[stage2_cnt]} = 
                find_max(stage1_max[base], stage1_max_idx[base],
                        stage1_max[base+1], stage1_max_idx[base+1],
                        stage1_max[base+2], stage1_max_idx[base+2],
                        stage1_max[base+3], stage1_max_idx[base+3],
                        stage1_max[base+4], stage1_max_idx[base+4]);
            {stage2_min[stage2_cnt], stage2_min_idx[stage2_cnt]} = 
                find_min(stage1_min[base], stage1_min_idx[base],
                        stage1_min[base+1], stage1_min_idx[base+1],
                        stage1_min[base+2], stage1_min_idx[base+2],
                        stage1_min[base+3], stage1_min_idx[base+3],
                        stage1_min[base+4], stage1_min_idx[base+4]);
            stage2_cnt <= stage2_cnt + 1;
        end

        // --------------------------------------------------
        // 第三级：最终比较
        // --------------------------------------------------
        if (stage2_cnt == 16) begin
            {final_max, final_max_idx} = 
                find_max(stage2_max[0], stage2_max_idx[0],
                        stage2_max[1], stage2_max_idx[1],
                        stage2_max[2], stage2_max_idx[2],
                        stage2_max[3], stage2_max_idx[3],
                        stage2_max[4], stage2_max_idx[4]);
            {final_min, final_min_idx} = 
                find_min(stage2_min[0], stage2_min_idx[0],
                        stage2_min[1], stage2_min_idx[1],
                        stage2_min[2], stage2_min_idx[2],
                        stage2_min[3], stage2_min_idx[3],
                        stage2_min[4], stage2_min_idx[4]);
            pipeline_done <= 1;
        end
    end
end

// ========================================================================
// 比较函数定义
// ========================================================================
function automatic [ADC_DATA_WIDTH+8:0] find_max;
    input [ADC_DATA_WIDTH-1:0] val0; input [8:0] idx0;
    input [ADC_DATA_WIDTH-1:0] val1; input [8:0] idx1;
    input [ADC_DATA_WIDTH-1:0] val2; input [8:0] idx2;
    input [ADC_DATA_WIDTH-1:0] val3; input [8:0] idx3;
    input [ADC_DATA_WIDTH-1:0] val4; input [8:0] idx4;
    begin
        reg [ADC_DATA_WIDTH-1:0] temp_val;
        reg [8:0] temp_idx;
        temp_val = val0;
        temp_idx = idx0;
        if (val1 > temp_val) begin temp_val = val1; temp_idx = idx1; end
        if (val2 > temp_val) begin temp_val = val2; temp_idx = idx2; end
        if (val3 > temp_val) begin temp_val = val3; temp_idx = idx3; end
        if (val4 > temp_val) begin temp_val = val4; temp_idx = idx4; end
        find_max = {temp_val, temp_idx};
    end
endfunction

function automatic [ADC_DATA_WIDTH+8:0] find_min;
    input [ADC_DATA_WIDTH-1:0] val0; input [8:0] idx0;
    input [ADC_DATA_WIDTH-1:0] val1; input [8:0] idx1;
    input [ADC_DATA_WIDTH-1:0] val2; input [8:0] idx2;
    input [ADC_DATA_WIDTH-1:0] val3; input [8:0] idx3;
    input [ADC_DATA_WIDTH-1:0] val4; input [8:0] idx4;
    begin
        reg [ADC_DATA_WIDTH-1:0] temp_val;
        reg [8:0] temp_idx;
        temp_val = val0;
        temp_idx = idx0;
        if (val1 < temp_val) begin temp_val = val1; temp_idx = idx1; end
        if (val2 < temp_val) begin temp_val = val2; temp_idx = idx2; end
        if (val3 < temp_val) begin temp_val = val3; temp_idx = idx3; end
        if (val4 < temp_val) begin temp_val = val4; temp_idx = idx4; end
        find_min = {temp_val, temp_idx};
    end
endfunction

// ========================================================================
// 寄存器与存储器接口
// ========================================================================
reg [15:0] handle_state;  // 处理状态寄存器

always @(posedge clk) begin
    if (pipeline_done) handle_state <= 1;
    else if (current_state == IDLE) handle_state <= 0;
end

// 低频状态更新
always @(posedge clk) begin
    if (!reset_n) low_state <= 1;
    else if (low_count >= 200) low_state <= 2;
    else low_state <= 1;
end

// 地址解码与数据输出
wire [13:0] addr = rd_data[13:0];  // 提取地址位

always @(posedge clk) begin
    if (en) begin
        if (addr[13]) begin  // 寄存器访问
            case(addr)
                14'h2000: wr_data <= handle_state;
                14'h2001: wr_data <= low_count;
                14'h2002: wr_data <= {14'b0, low_state};
                default:  wr_data <= 16'hDEAD;
            endcase
        end
        else begin  // 存储器访问
            if (addr < 400)
                wr_data <= {4'b0, data_buffer[addr]};  // 12位扩展为16位
            else
                wr_data <= 16'hFFFF;
        end
    end
    else begin
        wr_data <= 16'hZZZZ;  // 高阻态
    end
end

endmodule