// 自相关计算模块
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

// 跨时钟域同步单元
(* ASYNC_REG = "TRUE" *) reg [DATA_WIDTH:0] sync_data[0:2]; // 带符号扩展

// 滑动窗口寄存器
reg signed [DATA_WIDTH:0] window [0:2*MAX_TAU-1]; // 512深度窗口
reg [9:0] wr_ptr = 0;

// 增量相关值存储
reg signed [31:0] corr_values [0:MAX_TAU-1];
reg [1:0] state = 0;

// 稳定检测相关
reg [15:0] history [0:2];
reg [1:0] hist_ptr = 0;
reg [15:0] variance = 0;

// 跨时钟域同步处理
always @(negedge adc_clk) begin
    sync_data[0] <= {data_in[DATA_WIDTH-1], data_in}; // 符号扩展
end

always @(posedge clk) begin
    // 同步数据链
    sync_data[1] <= sync_data[0];
    sync_data[2] <= sync_data[1];
end

wire adc_clk_falling = !adc_clk && adc_clk_falling;// 下降沿

// 主处理逻辑
always @(posedge clk) begin
    if(!en)begin
        // 初始化复位
        for(int i=0; i<2*MAX_TAU; i++) window[i] = 0;
        for(int j=0; j<MAX_TAU; j++) corr_values[j] = 0;
        stable = 0;
    end else begin
        case(state)
            0: begin // 等待新数据
                if(adc_clk_falling) begin // adc_clk下降沿
                    // 更新滑动窗口
                    window[wr_ptr] <= sync_data[2];
                    wr_ptr <= (wr_ptr == 2*MAX_TAU-1) ? 0 : wr_ptr + 1;
                    
                    // 启动增量计算
                    state <= 1;
                end
            end
            
            1: begin // 并行计算相关值
                for(int i=0; i<MAX_TAU; i++) begin
                    automatic integer idx_old = (wr_ptr - i - MAX_TAU + 2*MAX_TAU) % (2*MAX_TAU);
                    corr_values[i] <= corr_values[i] + 
                        window[(wr_ptr - i + 2*MAX_TAU) % (2*MAX_TAU)] * sync_data[2] -
                        window[idx_old] * window[(idx_old + i) % (2*MAX_TAU)];
                end
                state <= 2;
            end
            
            2: begin // 峰值检测
                reg [31:0] max_val = 0;
                reg [8:0] peak_idx = 50; // 忽略前50个点
                for(int j=50; j<MAX_TAU; j++) begin
                    if(corr_values[j] > max_val) begin
                        max_val = corr_values[j];
                        peak_idx = j;
                    end
                end
                
                // 更新历史记录
                history[hist_ptr] <= peak_idx;
                hist_ptr <= hist_ptr + 1;
                
                // 计算稳定性
                if(hist_ptr == 2) begin
                    reg [15:0] avg = (history[0] + history[1] + history[2]) / 3;
                    variance = ((history[0]-avg)**2 + (history[1]-avg)**2 + (history[2]-avg)**2)/3;
                    stable <= (variance < (avg >> 5)); // 约3%容差
                    period <= avg << 1; // 转换为完整周期
                end
                
                state <= 0;
            end
        endcase
    end

end


endmodule