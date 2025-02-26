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

    // ================= 锁相环 =================
    wire c0, c1, locked;
    my_pll my_pll_inst (
        .areset  (~reset_n), // 关键：低有效转高有效
        .inclk0  (clk),
        .c0      (c0),// 20MHz
        .c1      (c1),// 200MHz
        .locked  (locked)
    );

    // 新的复位信号
    wire combined_reset_n = reset_n & locked;  // 当 reset_n=1 且 locked=1 时，复位解除
    reg sync_reset_n;// 同步复位信号
    always_ff @(posedge clk) begin
        sync_reset_n <= combined_reset_n;
    end

    // ================= 用户接口 =================
    logic [15:0] rd_data;
    logic [15:0] wr_data;
    logic          state;       // 1:读 0:写
    logic [3:0]       cs;


    // ================= 用户模块 =================
    fsmc_interface fsmc(
        .AD(AD),
        .NADV(NADV),
        .NWE(NWE),
        .NOE(NOE),
        .clk(c1),
        .reset_n(sync_reset_n),
        .rd_data(rd_data),
        .wr_data(wr_data),
        .state(state),
        .cs(cs)
    );

    test_reg test_reg(
        .clk(c1),
        .reset_n(sync_reset_n),
        .en(cs[0]),
        .rd_data(rd_data),
        .wr_data(wr_data),
        .state(state)
    );


endmodule