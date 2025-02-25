// 如果读取的值是0xFFFF，那么说明片选条件未正常响应
module test_reg #(
    parameter DATA_WIDTH = 16              // 数据位宽
)(
    // ================= 系统接口 =================
    input         clk,                // 主时钟
    input         reset_n,            // 异步复位
    
    // ================= 用户接口 =================
    input         en,                 // 使能信号
    input  [DATA_WIDTH-1:0] rd_data,  // 读数据输入
    output [DATA_WIDTH-1:0] wr_data,  // 写数据输出
    input        state                // 状态指示（0:读 1:写）
);

reg [DATA_WIDTH-1:0] stored_data;     // 数据存储寄存器
reg pre_en;                           // 使能信号延迟寄存器

wire en_falling = pre_en & ~en;       // 边沿检测

// 边沿检测逻辑
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        pre_en <= 1'b0;
    end else begin
        pre_en <= en;
    end
end

// 状态控制与数据存储
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        stored_data <= {DATA_WIDTH{1'b0}};
    end else begin
        // 检测en下降沿
        if (en_falling && ~state) begin      
            stored_data <= rd_data;
        end
    end
end

// 写数据输出控制（组合逻辑直接输出）
assign wr_data = (state & en) ? stored_data : {DATA_WIDTH{1'b1}};


endmodule