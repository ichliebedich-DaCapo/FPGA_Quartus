`timescale 1ns/1ps

module tb_auto_gain_control();

reg         clk;
reg         adc_clk;
reg         rst_n;
reg  [11:0] adc_data;
wire [1:0]  relay_ctrl;
wire        stable;

auto_gain_control uut (
    .clk(clk),
    .adc_clk(adc_clk),
    .rst_n(rst_n),
    .adc_data(adc_data),
    .relay_ctrl(relay_ctrl),
    .stable(stable)
);

// 时钟生成
always #5 clk = ~clk;      // 100MHz时钟
always #500 adc_clk = ~adc_clk; // 1MHz采样时钟

// ADC参考电压参数
localparam VREF = 2.0;     // 2V参考电压
localparam LSB = VREF/4096;

task adc_drive;
    input real voltage;
    begin
        adc_data = $rtoi(voltage / LSB);
    end
endtask

initial begin
    // 初始化
    clk = 0;
    adc_clk = 0;
    rst_n = 0;
    adc_data = 0;
    
    // 复位过程
    #100 rst_n = 1;
    
    // 测试案例1：初始状态验证
    $display("\n=== Test Case 1: Initial State ===");
    adc_drive(0.9);  // 初始应在最低增益（3x）
    #2000 check_state(2'b00, 1'b1, "Initial state");
    
    // 测试案例2：逐步提升增益
    $display("\n=== Test Case 2: Gain Increasing ===");
    test_gain_increase();
    
    // 测试案例3：超限保护测试
    $display("\n=== Test Case 3: Over-range Protection ===");
    test_over_range();
    
    // 测试案例4：滞回效应测试
    $display("\n=== Test Case 4: Hysteresis Test ===");
    test_hysteresis();
    
    // 测试案例5：稳定机制测试
    $display("\n=== Test Case 5: Stability Mechanism ===");
    test_stability();
    
    #100 $finish;
end

//--------------------------
// 测试子程序
//--------------------------

task check_state;
    input [1:0] exp_relay;
    input       exp_stable;
    input string msg;
    begin
        if (relay_ctrl !== exp_relay || stable !== exp_stable) begin
            $display("[ERROR] %t: %s", $time, msg);
            $display("  Expected: relay=%b stable=%b", exp_relay, exp_stable);
            $display("  Actual:   relay=%b stable=%b", relay_ctrl, stable);
        end
        else begin
            $display("[PASS] %t: %s", $time, msg);
        end
    end
endtask

task test_gain_increase;
    begin
        // 触发增益提升
        adc_drive(0.3);  // 300mV输入，3x增益输出900mV（低于875mV阈值）
        #2000 check_state(2'b01, 1'b1, "Gain increased to 6.5x");
        
        adc_drive(0.15); // 150mV输入，6.5x增益输出975mV
        #2000 check_state(2'b10, 1'b1, "Gain increased to 13.5x");
        
        adc_drive(0.07); // 70mV输入，13.5x增益输出945mV
        #2000 check_state(2'b11, 1'b1, "Gain increased to 29.25x");
    end
endtask

task test_over_range;
    begin
        // 触发超限保护
        adc_drive(0.8);  // 800mV输入，29.25x增益输出2340mV（超过1895mV）
        #2000 check_state(2'b10, 1'b1, "Over-range protection");
    end
endtask

task test_hysteresis;
    begin
        // 精确滞回测试
        adc_drive(0.875 - 0.05); // 低于滞回窗口
        #2000 check_state(2'b10, 1'b1, "Below hysteresis");
        
        adc_drive(0.875 - 0.03); // 在滞回窗口内（不应触发）
        #2000 check_state(2'b10, 1'b1, "Within hysteresis");
        
        adc_drive(0.875 - 0.06); // 超出滞回窗口
        #2000 check_state(2'b11, 1'b1, "Cross hysteresis");
    end
endtask

task test_stability;
    begin
        // 快速变化测试
        adc_drive(1.8);  // 触发降增益
        #100 adc_drive(0.5);  // 在稳定期内改变数值
        #2000 check_state(2'b01, 1'b1, "Stability period check");
    end
endtask

// 波形记录
initial begin
    $dumpfile("wave.vcd");
    $dumpvars(0, tb_auto_gain_control);
end

endmodule