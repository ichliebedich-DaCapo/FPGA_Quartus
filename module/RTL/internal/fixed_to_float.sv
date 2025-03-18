// 转换为浮点数
module fixed_to_float #(
    parameter FIXED_WIDTH = 12,
    parameter EXP_WIDTH = 8,// 指数位宽
    parameter MANT_WIDTH = 23
)(
    input clk,
    input areset,       // 异步复位
    input [FIXED_WIDTH-1:0] a,  // 12位有符号输入
    output reg [EXP_WIDTH+MANT_WIDTH:0] q  // 单精度浮点输出
);

// ================== 流水线级定义 ==================
localparam PIPELINE_STAGES = 3;

// 符号处理
reg [FIXED_WIDTH:0] stage1_abs;
reg stage1_sign;

// 前导零检测
reg [4:0] stage2_leading_ones;
reg [FIXED_WIDTH:0] stage2_value;

// 指数/尾数计算
reg [EXP_WIDTH-1:0] stage3_exp;
reg [MANT_WIDTH-1:0] stage3_mant;
reg stage3_sign;

// ================== 主转换逻辑 ==================
always @(posedge clk or posedge areset) begin
    if (areset) begin
        // 流水线复位
        {stage1_abs, stage1_sign} <= 0;
        {stage2_leading_ones, stage2_value} <= 0;
        {stage3_exp, stage3_mant, stage3_sign} <= 0;
    end else begin
        // Stage 1: 符号处理
        stage1_sign <= a[FIXED_WIDTH-1];
        stage1_abs <= stage1_sign ? 
            (~{1'b0, a} + 1) :  // 负数取补码
            {1'b0, a};          // 正数直接扩展

        // Stage 2: 前导零检测
        reg [4:0] lz = 0;
        for (int i = FIXED_WIDTH; i >= 0; i--) begin
            if (stage1_abs[i]) begin
                lz = FIXED_WIDTH - i;
                break;
            end
        end
        stage2_leading_ones <= lz;
        stage2_value <= stage1_abs;

        // Stage 3: 指数和尾数计算
        if (stage2_value == 0) begin
            // 零值特判
            stage3_exp <= 8'h00;
            stage3_mant <= 23'h000000;
        end else begin
            // 指数计算（偏移127 + 有效位移）
            stage3_exp <= 127 + (FIXED_WIDTH - stage2_leading_ones - 1);
            
            // 尾数移位对齐（保留23位有效位）
            reg [FIXED_WIDTH+MANT_WIDTH:0] shifted = 
                stage2_value << (MANT_WIDTH - (FIXED_WIDTH - stage2_leading_ones));
            stage3_mant <= shifted[MANT_WIDTH-1:0];
        end
        stage3_sign <= stage1_sign;
    end
end

// ================== 最终输出 ==================
always @(posedge clk) begin
    q <= {stage3_sign, stage3_exp, stage3_mant};
end

endmodule