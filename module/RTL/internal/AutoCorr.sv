// 自相关计算模块，用于检测1024个数据的周期，采用无独立缓冲区的实时自相关架构，只需大小为512的必要缓冲区
module AutoCorr #(
    parameter DATA_WIDTH = 12  // 数据位宽
)(
    input clk,                  // 200MHz主时钟
    input adc_clk,              // 10MHzADC时钟,在下降沿处更新data_in数据
    input en,                   // 高电平说明去直流数据有效，连接至去直流模块 DC_Removal.en
    input reg signed [DATA_WIDTH-1:0] data_in, // 来自去直流模块的数据
    output reg [15:0] period,     // 检测周期
    output reg stable   // 高电平为稳定
);

// ================= 跨时钟域处理 =================
reg signed[DATA_WIDTH-1:0] cdc_buffer[0:1];
reg adc_clk_dly;

always @(negedge adc_clk) begin
    cdc_buffer[0] <= data_in;  // ADC下降沿捕获数据
end

always @(posedge clk) begin
    adc_clk_dly <= adc_clk;
    if (adc_clk && !adc_clk_dly) begin  // 检测ADC时钟上升沿
        cdc_buffer[1] <= cdc_buffer[0];  // 同步到200MHz域
    end
end

// ================= FFT配置参数 =================
localparam FFT_LENGTH = 1024;
localparam FFT_DW = 32;  // 单精度浮点位宽

// ================= 浮点转换模块 =================
wire [FFT_DW-1:0] float_data;
fixed_to_float u_convert (
    .clk    (clk),
    .areset (1'b0),
    .a      (cdc_buffer[1]),
    .q      (float_data)
);

// ================= FFT控制状态机 =================
typedef enum {
    IDLE,
    COLLECT_DATA,
    FFT_PROCESSING,
    IFFT_PROCESSING,
    PEAK_DETECTION
} state_t;

reg [2:0] state = IDLE;
reg [10:0] data_counter = 0;
reg [FFT_DW-1:0] fft_input_buffer[0:FFT_LENGTH-1];

// ================= FFT实例化 =================
wire fft_sink_ready;
reg fft_sink_valid;
reg fft_sink_sop;
reg fft_sink_eop;
wire [FFT_DW-1:0] fft_source_real;
wire [FFT_DW-1:0] fft_source_imag;
wire fft_source_valid;

fft_1024 u_fft (
    .clk          (clk),
    .reset_n      (1'b1),
    .sink_valid   (fft_sink_valid),
    .sink_ready   (fft_sink_ready),
    .sink_error   (2'b00),
    .sink_sop     (fft_sink_sop),
    .sink_eop     (fft_sink_eop),
    .sink_real    (fft_input_buffer[data_counter]),
    .sink_imag    (32'h0000_0000),
    .fftpts_in    (10'd1024),
    .source_valid (fft_source_valid),
    .source_ready (1'b1),
    .source_real  (fft_source_real),
    .source_imag  (fft_source_imag)
);

// ================= 功率谱计算 =================
reg [FFT_DW-1:0] power_spectrum[0:FFT_LENGTH-1];
reg [10:0] power_counter;

always @(posedge clk) begin
    if (fft_source_valid) begin
        power_spectrum[power_counter] <= 
            fft_source_real * fft_source_real +
            fft_source_imag * fft_source_imag;
        power_counter <= (power_counter == FFT_LENGTH-1) ? 0 : power_counter + 1;
    end
end

// ================= IFFT控制 =================
reg ifft_sink_valid;
reg ifft_sink_sop;
reg ifft_sink_eop;
wire [FFT_DW-1:0] ifft_source_real;
wire [FFT_DW-1:0] ifft_source_imag;
wire ifft_source_valid;

fft_1024 u_ifft (
    .clk          (clk),
    .reset_n      (1'b1),
    .sink_valid   (ifft_sink_valid),
    .sink_ready   (),
    .sink_error   (2'b00),
    .sink_sop     (ifft_sink_sop),
    .sink_eop     (ifft_sink_eop),
    .sink_real    (power_spectrum[power_counter]),
    .sink_imag    (32'h0000_0000),
    .fftpts_in    (10'd1024),
    .source_valid (ifft_source_valid),
    .source_ready (1'b1),
    .source_real  (ifft_source_real),
    .source_imag  (ifft_source_imag)
);

// ================= 自相关缓冲区 =================
reg [FFT_DW-1:0] ac_buffer[0:511];  // 512点有效数据
reg [9:0] ac_counter;

// ================= 峰值检测 =================
reg [15:0] max_value = 0;
reg [15:0] second_max = 0;
reg [9:0] peak_index = 0;

always @(posedge clk) begin
    if (ifft_source_valid) begin
        // 存储前512点
        if (ac_counter < 511) begin
            ac_buffer[ac_counter] <= ifft_source_real;
            ac_counter <= ac_counter + 1;
            
            // 峰值检测逻辑
            if (ac_counter > 0) begin  // 跳过k=0
                if (ifft_source_real > max_value) begin
                    second_max <= max_value;
                    max_value <= ifft_source_real;
                    peak_index <= ac_counter;
                end else if (ifft_source_real > second_max) begin
                    second_max <= ifft_source_real;
                end
            end
        end else begin
            // 完成检测
            period <= peak_index;
            stable <= (second_max > (max_value >> 1));  // 稳定性判断
            ac_counter <= 0;
            max_value <= 0;
            second_max <= 0;
        end
    end
end

// ================= 主控制逻辑 =================
always @(posedge clk) begin
    case (state)
        IDLE: 
            if (en) begin
                state <= COLLECT_DATA;
                data_counter <= 0;
            end
            
        COLLECT_DATA:
            if (data_counter < FFT_LENGTH-1) begin
                fft_input_buffer[data_counter] <= float_data;
                data_counter <= data_counter + 1;
            end else begin
                state <= FFT_PROCESSING;
                fft_sink_valid <= 1;
                fft_sink_sop <= 1;
            end
            
        FFT_PROCESSING:
            if (fft_sink_ready) begin
                fft_sink_sop <= 0;
                if (data_counter == FFT_LENGTH-1) begin
                    fft_sink_eop <= 1;
                    state <= IFFT_PROCESSING;
                end
                data_counter <= data_counter + 1;
            end
            
        IFFT_PROCESSING:
            if (ifft_source_valid) begin
                state <= PEAK_DETECTION;
            end
            
        PEAK_DETECTION:
            if (ac_counter == 511) begin
                state <= IDLE;
            end
    endcase
end

endmodule