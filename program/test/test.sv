module test(
    // ================= 物理接口 =================
    inout  [17:0] AD,      // 复用地址/数据总线
    input         NADV,               // 地址有效指示（低有效）
    input         NWE,                // 写使能（低有效）
    input         NOE,                // 读使能（低有效）
    
    // ================= 系统接口 =================
    input         clk,                // 主时钟
    input         reset_n            // 异步复位

);

    // ================= 用户接口 =================
    logic [15:0] rd_data;
    logic [15:0] wr_data;
    logic          state;       // 1:读 0:写
    logic [3:0]       cs;

    fsmc_interface fsmc(
        .AD(AD),
        .NADV(NADV),
        .NWE(NWE),
        .NOE(NOE),
        .clk(clk),
        .reset_n(reset_n),
        .rd_data(rd_data),
        .wr_data(wr_data),
        .state(state),
        .cs(cs)
    );

    test_reg test_reg(
        .clk(clk),
        .reset_n(reset_n),
        .en(cs[0]),
        .rd_data(rd_data),
        .wr_data(wr_data),
        .state(state)
    );


endmodule