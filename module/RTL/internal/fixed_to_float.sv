module fixed_to_float #(
    parameter FIXED_WIDTH = 12,
    parameter EXP_WIDTH = 8,    // 指数位宽
    parameter MANT_WIDTH = 23
)(
    input clk,
    input rst_n,               // 异步复位
    input signed [FIXED_WIDTH-1:0] a,  // 修正点1：输入端口不能声明为 reg
    output reg [EXP_WIDTH+MANT_WIDTH:0] q  // 单精度浮点输出
);

// ================== 流水线寄存器定义 ==================
localparam PIPELINE_STAGES = 3;

// Stage 1: 符号处理
reg [FIXED_WIDTH:0] stage1_abs;
reg stage1_sign;

// Stage 2: 前导零检测
reg [4:0] stage2_lz;
reg [FIXED_WIDTH:0] stage2_abs;

// Stage 3: 指数/尾数计算
reg [EXP_WIDTH-1:0] stage3_exp;
reg [MANT_WIDTH-1:0] stage3_mant;
reg stage3_sign;
reg [FIXED_WIDTH+MANT_WIDTH:0] shifted; // 声明足够宽的移位寄存器
// ================== 主转换逻辑 ==================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        {stage1_abs, stage1_sign} <= 0;
        {stage2_lz, stage2_abs} <= 0;
        {stage3_exp, stage3_mant, stage3_sign} <= 0;
    end else begin
        // Stage 1: 计算绝对值（处理补码）
        stage1_sign <= a[FIXED_WIDTH-1];
        if (a[FIXED_WIDTH-1]) begin
            // 正确计算补码（整个数值部分取反加1）
            stage1_abs <= {1'b0, (~a + 1)};  // 关键修正
        end else begin
            stage1_abs <= {1'b0, a};
        end

        // Stage 2: 前导零检测
        stage2_abs <= stage1_abs;
        stage2_lz <= FIXED_WIDTH; // 默认最大值
        for (int i = FIXED_WIDTH; i >= 0; i--) begin
            if (stage1_abs[i]) begin
                stage2_lz <= FIXED_WIDTH - i;
                break;
            end
        end

        // Stage 3: 计算指数和尾数
        stage3_sign <= stage1_sign;
        if (stage2_abs == 0) begin
            stage3_exp <= 0;
            stage3_mant <= 0;
        end else begin
            // 指数计算
            stage3_exp <= 127 + (FIXED_WIDTH - stage2_lz);
            
            // 尾数移位（分步操作解决语法错误）
            shifted = stage2_abs << (MANT_WIDTH - (FIXED_WIDTH - stage2_lz));
            stage3_mant <= shifted[MANT_WIDTH-1:0]; // 正确截取尾数
        end
    end
end

// ================== 最终输出 ==================
always @(posedge clk) begin
    q <= {stage3_sign, stage3_exp, stage3_mant};
end

endmodule