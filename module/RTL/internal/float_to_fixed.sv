// 失败的浮点转定点模块
module float_to_fixed #(
    parameter FIXED_WIDTH = 12,
    parameter EXP_WIDTH = 8,
    parameter MANT_WIDTH = 23
)(
    input clk,
    input rst_n,
    input [31:0] a,  // 浮点输入（符号1b，指数8b，尾数23b）
    output reg signed [FIXED_WIDTH-1:0] q,  // 定点输出
    output reg en
);

// ================== 流水线寄存器定义 ==================
// Stage 1: 输入解析和基本参数计算
reg stage1_sign;
reg [EXP_WIDTH-1:0] stage1_exp;
reg [MANT_WIDTH-1:0] stage1_mant;
reg stage1_is_zero;
reg stage1_is_denorm;
reg stage1_is_special;
reg signed [9:0] stage1_exp_val;  // 带符号指数（扩展2bit）
reg stage1_valid;

// Stage 2: 尾数处理和移位计算
reg [23:0] stage2_mant;          // 隐含1的尾数
reg signed [9:0] stage2_exp_val;
reg stage2_sign;
reg stage2_is_zero;
reg stage2_is_special;
reg [31:0] stage2_shifted;      // 移位结果（足够大位宽）
reg stage2_valid;

// Stage 3: 溢出处理和最终结果
reg signed [FIXED_WIDTH:0] stage3_result;  // 带1bit溢出检测
reg stage3_valid;
reg signed [31:0] signed_value;

// ================== 常量定义 ==================
localparam MAX_POS = (2**(FIXED_WIDTH-1))-1;
localparam MAX_NEG = -(2**(FIXED_WIDTH-1));

integer shift;
reg [31:0] abs_value;
// ================== 主转换逻辑 ==================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // Stage 1 复位
        {stage1_sign, stage1_exp, stage1_mant, stage1_is_zero,
         stage1_is_denorm, stage1_is_special, stage1_exp_val, stage1_valid} <= 0;
        
        // Stage 2 复位
        {stage2_mant, stage2_exp_val, stage2_sign, stage2_is_zero,
         stage2_is_special, stage2_shifted, stage2_valid} <= 0;
        
        // Stage 3 复位
        {stage3_result, stage3_valid} <= 0;
        en <= 0;
    end else begin
        // ========== Stage 1: 输入解析 ==========
        stage1_sign <= a[31];
        stage1_exp <= a[30:23];
        stage1_mant <= a[22:0];
        stage1_valid <= 1'b1;

        // 零和非规格化判断
        stage1_is_zero <= (a[30:23] == 0) & (a[22:0] == 0);
        stage1_is_denorm <= (a[30:23] == 0) & (a[22:0] != 0);
        
        // 特殊值判断（无穷大/NaN）
        stage1_is_special <= (a[30:23] == 8'hFF);
        
        // 指数计算（有符号）
        stage1_exp_val <= (a[30:23] == 0) ? 10'sd0 : 
                         ($signed({1'b0, a[30:23]}) - 10'sd127);

        // ========== Stage 2: 移位计算 ==========
        stage2_sign <= stage1_sign;
        stage2_exp_val <= stage1_exp_val;
        stage2_valid <= stage1_valid;
        stage2_is_zero <= stage1_is_zero | stage1_is_denorm;
        stage2_is_special <= stage1_is_special;
        
        // 生成带隐含位的尾数
        stage2_mant <= {1'b1, stage1_mant};

        // 移位逻辑
        if (stage1_is_zero | stage1_is_denorm) begin
            stage2_shifted <= 0;
        end else if (stage1_exp_val < 0) begin
            stage2_shifted <= 0;
        end else begin
            if (stage1_exp_val >= 10'sd23) begin
                shift = stage1_exp_val - 10'sd23;
                stage2_shifted <= (shift > 31) ? 0 : (stage2_mant << shift);
            end else begin
                shift = 10'sd23 - stage1_exp_val;
                stage2_shifted <= stage2_mant >> shift;
            end
        end

        // ========== Stage 3: 结果处理 ==========
        stage3_valid <= stage2_valid;
        
        if (stage2_is_zero) begin
            stage3_result <= 0;
        end else if (stage2_is_special) begin  // 处理无穷大/NaN
            stage3_result <= stage2_sign ? MAX_NEG : MAX_POS;
        end else begin
            // 符号扩展处理
            abs_value = stage2_shifted;

            // 溢出检测
            if (stage2_sign) begin
                signed_value = (abs_value > (MAX_NEG * -1)) ? 
                               MAX_NEG : -abs_value;
            end else begin
                signed_value = (abs_value > MAX_POS) ? 
                               MAX_POS : abs_value;
            end

            // 截断到目标位宽
            stage3_result <= signed_value[FIXED_WIDTH:0];
        end

        // 流水线就绪信号
        en <= stage1_valid & stage2_valid & stage3_valid;
    end
end

// ================== 输出赋值 ==================
always @(posedge clk) begin
    q <= stage3_result[FIXED_WIDTH-1:0];
end

endmodule