// 自相关计算模块，用于检测1024个数据的周期，采用无独立缓冲区的实时自相关架构，只需大小为512的必要缓冲区
module AutoCorr #(
    parameter DATA_WIDTH = 12,  // 数据位宽
    parameter MAX_TAU = 256     // 最大延迟点数
)(
    input clk,                  // 200MHz主时钟
    input adc_clk,              // 10MHzADC时钟,在下降沿处更新data_in数据
    input en,                   // 高电平说明去直流数据有效，连接至去直流模块 DC_Removal.en
    input reg signed [DATA_WIDTH-1:0] data_in, // 来自去直流模块的数据
    output reg [15:0] period,     // 检测周期
    output stable   // 高电平为稳定
);

// ===========跨时钟域同步=============
(* ASYNC_REG = "TRUE" *) reg [DATA_WIDTH:0] sync_data[0:2];
(* ASYNC_REG = "TRUE" *) reg [2:0] en_sync;

reg [1:0] adc_clk_sync;

wire en_valid = en_sync[2];

// 数据同步链
always @(negedge adc_clk) sync_data[0] <= {data_in[DATA_WIDTH-1], data_in};
always @(posedge clk) begin
    adc_clk_sync <= {adc_clk_sync[1:0], adc_clk};
    sync_data[1] <= sync_data[0];
    en_sync <= {en_sync[1:0], en};
end
wire adc_clk_falling = ~adc_clk_sync[1] & adc_clk_sync[0];// adc_clk下降沿

// 滑动窗口
reg signed [DATA_WIDTH:0] window [0:2*MAX_TAU-1];
reg [9:0] wr_ptr;

// 相关值存储
reg signed [31:0] corr_values [0:MAX_TAU-1];
reg signed [33:0] calc,variance,avg;

reg [1:0] state;

// 稳定检测
reg [15:0] history[0:2];
reg [1:0] hist_ptr;

// ============状态机=============
always @(posedge clk) begin
    if(!en_valid) begin
        wr_ptr <= 0;
        state <= 0;
        stable <= 0;
        for(int i=0; i<2*MAX_TAU; i++) window[i] = 0;
        for(int j=0; j<MAX_TAU; j++) corr_values[j] = 0;
    end else begin
        case(state)
            0: begin
                if(adc_clk_falling) begin
                    window[wr_ptr] <= sync_data[2];
                    wr_ptr <= (wr_ptr == 2*MAX_TAU-1) ? 0 : wr_ptr + 1;
                    state <= 1;
                end
            end
            
            1: begin
                for(int i=0; i<MAX_TAU; i++) begin
                    automatic integer idx_new = (wr_ptr - i + 2*MAX_TAU) % (2*MAX_TAU);
                    automatic integer idx_old = (wr_ptr - i - MAX_TAU + 2*MAX_TAU) % (2*MAX_TAU);
                    calc = corr_values[i] + window[idx_new] * sync_data[2] - 
                        window[idx_old] * window[(idx_old + i) % (2*MAX_TAU)];
                    corr_values[i] <= (|calc[33:31]) ? 32'h7FFF_FFFF : calc[31:0];
                end
                state <= 2;
            end
            
            2: begin
                reg [31:0] max_val = 0;
                reg [8:0] peak_idx = 10; // 最小周期保护
                for(int j=10; j<MAX_TAU; j++) begin
                    if(corr_values[j] > max_val) begin
                        max_val = corr_values[j];
                        peak_idx = j;
                    end
                end
                
                // 更新历史
                history[hist_ptr] <= peak_idx;
                hist_ptr <= (hist_ptr == 2) ? 0 : hist_ptr + 1;
                
                // 稳定性判断
                if(hist_ptr == 2) begin
                    avg = (history[0] + history[1] + history[2]) / 3;
                    variance = ((history[0]-avg)**2 + (history[1]-avg)**2 + (history[2]-avg)**2);
                    stable <= (variance * 100 < avg * 3);
                    period <= avg; // 移除左移
                end
                state <= 0;
            end
        endcase
    end
end



endmodule