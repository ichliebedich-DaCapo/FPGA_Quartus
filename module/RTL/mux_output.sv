module mux_output #(
    parameter N = 4, // 内部模块的数量
    parameter WIDTH = 16 // 输出宽度
)(
    input clk,
    input reset,
    input [$clog2(N)-1:0] cs_addr, // 片选地址
    input wire [WIDTH-1:0] module_outputs [0:N-1], // 内部模块的输出
    output reg [WIDTH-1:0] output_to_mc // 输出到单片机
);

    always_ff @(posedge clk or negedge reset) begin
        if (!reset) begin
            output_to_mc <= '0; // 复位时输出为0
        end else begin
            // 根据片选地址选择输出
            case (cs_addr)
                // 每个case对应一个内部模块的输出
                0: output_to_mc <= module_outputs[0];
                1: output_to_mc <= module_outputs[1];
                // 继续添加其他case语句...
                default: output_to_mc <= module_outputs[N-1]; // 默认选择最后一个模块
            endcase
        end
    end
endmodule