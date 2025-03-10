module data_storage_and_process #(
    parameter DATA_WIDTH  = 16,
    parameter ADC_WIDTH   = 12,
    parameter BUF_SIZE    = 400,
    parameter ADDR_WIDTH  = 12
)(
    input  logic                 clk,
    input  logic                 rst_n,
    input  logic [DATA_WIDTH-1:0] rd_data,
    output logic [DATA_WIDTH-1:0] wr_data,
    input  logic                 state,
    input  logic                 en,
    input  logic                 trigger,
    input  logic [ADC_WIDTH-1:0] adc_data,
    input  logic                 adc_valid,
    input  logic                 high_speed_mode,
    input  logic                 pause
);

// 内部信号定义
logic [1:0]  buf_sel;
logic [8:0]  wr_ptr_h, rd_ptr_h;
logic [9:0]  wr_ptr_l, disp_ptr;
logic [11:0] addr_decoded;
logic        buf_full, data_valid_reg;
logic [15:0] peak2peak, peak_interval;
logic [15:0] fft_result[0:199];

// 双端口RAM定义
logic [ADC_WIDTH-1:0] buffer0[0:399];
logic [ADC_WIDTH-1:0] buffer1[0:399];
logic [ADC_WIDTH-1:0] low_buffer[0:399];

// 地址解码
assign addr_decoded = rd_data[ADDR_WIDTH-1:0];

// 状态机定义
typedef enum {
    IDLE,
    HI_WAIT_TRIGGER,
    HI_SAMPLING,
    HI_WAIT_READ,
    HI_TIMEOUT,
    LO_SAMPLING,
    LO_FULL
} fsm_state;

fsm_state current_state, next_state;

// 高频模式控制
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        current_state <= IDLE;
        buf_sel <= 0;
        wr_ptr_h <= 0;
        data_valid_reg <= 0;
    end else begin
        current_state <= next_state;
        
        case(current_state)
            HI_WAIT_TRIGGER: begin
                if(trigger) begin
                    wr_ptr_h <= 0;
                    buf_sel <= ~buf_sel;
                end
            end
            
            HI_SAMPLING: begin
                if(adc_valid && wr_ptr_h < 399)
                    wr_ptr_h <= wr_ptr_h + 1;
            end
            
            HI_WAIT_READ: begin
                if(addr_decoded == 16'h1000 && !state && en)
                    data_valid_reg <= wr_data[0];  // MCU写操作
            end
        endcase
    end
end

// 状态转移逻辑
always_comb begin
    next_state = current_state;
    case(current_state)
        IDLE: next_state = high_speed_mode ? HI_WAIT_TRIGGER : LO_SAMPLING;
        HI_WAIT_TRIGGER: if(trigger) next_state = HI_SAMPLING;
        HI_SAMPLING: begin
            if(wr_ptr_h == 399) begin
                if(data_valid_reg)
                    next_state = HI_TIMEOUT;
                else
                    next_state = HI_WAIT_READ;
            end
        end
        HI_TIMEOUT: if(wr_ptr_h == 199) next_state = HI_WAIT_TRIGGER;
        HI_WAIT_READ: if(!data_valid_reg) next_state = HI_WAIT_TRIGGER;
        LO_SAMPLING: if(wr_ptr_l == 399) next_state = LO_FULL;
        LO_FULL: next_state = LO_SAMPLING;
    endcase
end

// 低频模式控制
always_ff @(posedge clk) begin
    if(high_speed_mode) begin
        wr_ptr_l <= 0;
        disp_ptr <= 0;
    end else begin
        if(adc_valid) begin
            low_buffer[wr_ptr_l] <= adc_data;
            wr_ptr_l <= (wr_ptr_l == 399) ? 0 : wr_ptr_l + 1;
        end
    end
end

// 数据处理流水线
always_ff @(posedge clk) begin
    // 峰峰值检测
    static logic [ADC_WIDTH-1:0] max_val, min_val;
    if(adc_valid) begin
        max_val <= (adc_data > max_val) ? adc_data : max_val;
        min_val <= (adc_data < min_val) ? adc_data : min_val;
    end
    peak2peak <= max_val - min_val;
    
    // FFT计算（简化为示例）
    generate
        for(genvar i=0; i<200; i++) begin
            fft_result[i] <= buffer0[i] + buffer1[i]; // 简化处理
        end
    endgenerate
end

// 读写接口处理
always_ff @(posedge clk) begin
    if(en) begin
        if(state) begin // 写时序
            case(addr_decoded)
                16'h1000: data_valid_reg <= wr_data[0];
                // 其他寄存器扩展
            endcase
        end else begin // 读时序
            if(addr_decoded < 16'h1000) begin
                if(high_speed_mode) begin
                    wr_data <= (buf_sel) ? buffer1[addr_decoded[9:0]] : 
                                        buffer0[addr_decoded[9:0]];
                end else begin
                    wr_data <= low_buffer[(disp_ptr + addr_decoded[8:0])%400];
                end
            end else begin
                case(addr_decoded)
                    16'h1000: wr_data <= {15'b0, data_valid_reg};
                    16'h1001: wr_data <= peak2peak;
                    16'h1002: wr_data <= peak_interval;
                    default:  wr_data <= fft_result[addr_decoded[7:0]];
                endcase
            end
        end
    end
end

// 显示指针控制（滑动逻辑）
always_ff @(posedge clk) begin
    if(!high_speed_mode && en && state && 
       (addr_decoded == 16'h1003))
        disp_ptr <= wr_data[9:0];
end

endmodule