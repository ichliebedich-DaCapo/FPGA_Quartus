module fixed_to_float #(
    parameter FIXED_WIDTH = 12,
    parameter EXP_WIDTH = 8,    // 指数位宽
    parameter MANT_WIDTH = 23
)(
    input clk,
    input rst_n,               
    input signed [FIXED_WIDTH-1:0] a,  // 定点输入
    output reg [EXP_WIDTH+MANT_WIDTH:0] q, // 浮点输出
    output reg en                      // 流水线就绪信号
);

// ================== 流水线寄存器定义 ==================
// Stage 1: 符号处理
reg [FIXED_WIDTH:0] stage1_abs;
reg stage1_sign;
reg stage1_valid;  // 有效标志

// Stage 2: 前导零检测
reg [4:0] stage2_lz;
reg [FIXED_WIDTH:0] stage2_abs;
reg stage2_valid;

// Stage 3: 指数/尾数计算
reg [EXP_WIDTH-1:0] stage3_exp;
reg [MANT_WIDTH-1:0] stage3_mant;
reg stage3_sign;
reg stage3_valid;
reg [FIXED_WIDTH+MANT_WIDTH:0] shifted; // 声明足够宽的移位寄存器
// ================== 主转换逻辑 ==================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位所有寄存器
        {stage1_abs, stage1_sign, stage1_valid} <= 0;
        {stage2_lz, stage2_abs, stage2_valid} <= 0;
        {stage3_exp, stage3_mant, stage3_sign, stage3_valid} <= 0;
        en <= 0;
    end else begin
        // --- Stage 1: 符号和绝对值计算 ---
        stage1_sign <= a[FIXED_WIDTH-1];
        stage1_abs <= a[FIXED_WIDTH-1] ? {1'b0, (~a + 1)} : {1'b0, a};
        stage1_valid <= 1'b1; // 假设输入始终有效

        // --- Stage 2: 前导零检测 ---
        stage2_abs <= stage1_abs;
        stage2_valid <= stage1_valid;
        stage2_lz <= FIXED_WIDTH + 1; // 默认最大值
        for (int i = FIXED_WIDTH; i >= 0; i--) begin
            if (stage1_abs[i]) begin
                stage2_lz <= FIXED_WIDTH - i;
                break;
            end
        end

        // --- Stage 3: 指数和尾数计算 ---
        stage3_valid <= stage2_valid;
        stage3_sign <= stage1_sign;
        if (stage2_abs == 0) begin
            stage3_exp <= 0;
            stage3_mant <= 0;
        end else begin
            stage3_exp <= 127 + FIXED_WIDTH - stage2_lz;
            // 尾数移位（分步操作解决语法错误）
            shifted = stage2_abs << (MANT_WIDTH - (FIXED_WIDTH - stage2_lz));
            stage3_mant <= shifted[MANT_WIDTH-1:0]; // 正确截取尾数
        end

        // --- en信号生成：三级流水线均有效时拉高 ---
        en <= stage1_valid & stage2_valid & stage3_valid;
    end
end

// ================== 输出赋值 ==================
always @(posedge clk) begin
    q <= {stage3_sign, stage3_exp, stage3_mant};
end

endmodule