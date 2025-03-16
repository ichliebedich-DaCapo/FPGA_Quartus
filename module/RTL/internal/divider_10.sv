module divider_10 (
    input wire clk,          // 输入时钟
    input wire rst_n,          // 复位信号
    input wire [2:0] div,    // 分频系数选择,10^0~10^7分频（Hz）
    output reg ADC_CLK       // 输出时钟
);

reg [23:0] count;            // 计数器（支持最大分频系数1000）

// 预定义分频参数表（索引对应sel值）
localparam logic [23:0]  DIV_TABLE[0:7] = '{
    24'd0,   // sel=0: 2分频
    24'd9,   // sel=1: //10分频 (准确来说是20分频，但由于提前预支了2分频，那么可以理解为10分频，后面同理)
    24'd99,  // sel=2: 100分频 (100-1)
    24'd999,  // sel=3: 1000分频 (1000-1)
    24'd9999,  // sel=4: 10000分频 (10000-1)
    24'd99999,  // sel=5: 100000分频 (100000-1)
    24'd999999,  // sel=6: 1000000分频 (1000000-1)
    24'd9999999  // sel=7: 10000000分频 (10000000-1)
};

// 分频器核心逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin        // 复位或sel变化时初始化
        count <= 0;
        ADC_CLK <= 1'b0;
    end else if(count == DIV_TABLE[div]) begin
    // 0-9共10个状态，即10分频
        count <= 0;
        ADC_CLK <= ~ADC_CLK;
    end else begin
        count <= count + 1;
    end
end

endmodule