// 说明：
// 1，取消了电平触发检测不到后就不读取ADC数据
// 依赖：fractional_divider
// 

// `define DEBUG


module frequency_measure(
    // 接口端口定义
    input reset,              // 复位信号
    input clk,                // 时钟信号
    input en,
    output logic[15:0] module_out,
    input  [15:0] module_in,
    output logic notify,    // 通知线，表明模块数据已准备好
    output logic read_adc_result,// 读取ADC结果，暂时打算使用中断线来表示

    // ADC接口
    input [11:0] ADC_DATA,  // ADC数据输入
    output logic ADC_CLK, // ADC时钟输出
    output logic ADC_OE  // 低电平使能

    
    // // 为了调试
`ifdef DEBUG
    ,output [2:0] debug_state,
    output reg[1:0] debug_value,
    output reg debug_flag
`endif
);


    logic [15:0]N;// 分数分频器的整数部分
    logic [7:0]M;// 分数分频器分数部分的分子,16位数据的低8位
    logic [7:0]P;// 分数分频器分数部分的分母，16位数据的高8位
    
    // 分数分频器
    fractional_divider fractional_divider_inst(
        .reset(reset),
        .clk(clk),
        .N(N),
        .M(M),
        .P(P),
        .OUTPUT_CLK(ADC_CLK)
    );


    
    // 锁存模块地址
    // 00[000]：读存储器
    // 20[001]:读取ADC
    // 40[010]：分频器整数不分
    // 60[011]：分频器分数部分
    // 80[100]：触发阈值
    logic en_d;
    logic en_read;
    logic [2:0] addr_latch;
    reg [11:0]adc_trigger_threshold;// 触发阈值电平
    // reg [15:0]adc_read_result;// 读取结果
    reg [11:0] mem [0:399];       // 存储400个ADC采样数据的数组
    always_ff @(posedge clk or negedge reset)begin
        if(!reset)begin
            N ='0;
            M ='0;
            P ='0;
            en_d <= 1'b0;
            addr_latch <='0;
            adc_trigger_threshold <=16'd2000;
        end else begin
            en_d <= en;// 延迟
            if(~en_d & en)begin
                // 上升沿处根据此时地址输出数据
                addr_latch <= module_in[15:13]; 
                // 实时读取，避免读到addr_latch的初始状态（上一状态）
                case(module_in[15:13])
                    3'b000:begin
                        // 读存储器
                        module_out <= mem[module_in];
                    end
                    3'b001:begin
                        // 读取ADC
                        en_read <= 1;
                    end
                endcase
                
            end else if(en_d & ~en)begin
                // 下降沿读取模块数据
                case(addr_latch)
                    3'b010:begin
                        N <= module_in;
                    end
                    3'b011:begin
                        M <= module_in[7:0];
                        P <= module_in[15:8];
                    end
                    3'b100:begin
                        adc_trigger_threshold <= module_in[11:0];
                    end
                endcase
            end else begin
                en_read <= 1'b0;// 重置
            end

        end
    end


    // 内部信号定义
    typedef enum logic [2:0] {
        IDLE,
        WAIT_TRIGGER,
        INVALID,// 触发超时,无效数据
        SAMPLE_ADC,
        FINISH
    } state_t;

    state_t state, next_state;
    logic [9:0] trigger_counter;            // 计数器用于等待trigger或超时
    logic [8:0] sample_counter;     // 计数器用于记录ADC采样次数



    // 获取ADC_CLK的上升沿
    logic adc_clk_d;
    logic start_adc;
    always_ff @(posedge clk)begin
        adc_clk_d <= ADC_CLK;
        if(~adc_clk_d & ADC_CLK)begin
            start_adc <= 1;
        end else begin
            start_adc <='0;
        end
    end


    // 流水线
    logic [2:0]comparasion_results;
    logic final_comparasion_results;
    logic trigger_timeout_results;
    logic sample_counter_results;
    reg [11:0]adc_data_d;
    always_ff @(posedge clk)begin
        case(state)
            WAIT_TRIGGER:begin
                if(start_adc)begin
                    adc_data_d <= ADC_DATA;// 存储上个ADC数据
                    comparasion_results[0]=(ADC_DATA >= adc_trigger_threshold -40);
                    comparasion_results[1]=(ADC_DATA <= adc_trigger_threshold +60);
                    comparasion_results[2]=(ADC_DATA > adc_data_d+50);
                    final_comparasion_results <= (comparasion_results[0] & comparasion_results[1]& comparasion_results[2]);
                    trigger_counter <= trigger_counter + 1;
                    trigger_timeout_results <= (trigger_counter >= 400);
                end
            end
            SAMPLE_ADC:begin
                sample_counter_results <= (sample_counter < 400);
            end
            default:begin
                comparasion_results <= '0;
                final_comparasion_results <= '0;
                trigger_counter <= '0;
                trigger_timeout_results <= '0;
                sample_counter_results <= '1;
            end
        endcase
    end

    // 读取ADC状态机逻辑
    // 设定频率字之后，就不会卡死在SAMPLE_ADC状态了，那么这个重置状态就没什么用了
    always_ff @(posedge clk) begin
        state <= next_state;
        case (state)
            IDLE: begin
                if (en_read) begin
                    notify <= 1;
                    next_state <= WAIT_TRIGGER;
                    read_adc_result <= 1'b1;    // 读取时重置为1
                end
            end
            WAIT_TRIGGER: begin
                ADC_OE <='0;
                if(final_comparasion_results )begin
                    next_state <= SAMPLE_ADC;
                end else if(trigger_timeout_results)begin
                    next_state <= SAMPLE_ADC;
                    read_adc_result <= 1'b0;// 读取失败，转为0，直到下一次读取
                end
            end
            SAMPLE_ADC: begin
                if(sample_counter_results)begin
                    if(start_adc)begin
                        mem[sample_counter] <= ADC_DATA;
                        sample_counter <= sample_counter + 1;
                    end
                end else begin
                    next_state <= FINISH;
                end
            end
            // 包含了 FINISH 状态
            default: begin
                notify <='0;
                sample_counter <='0;
                next_state <= IDLE;
                ADC_OE <= 1;
            end
        endcase
    end












    // 调试
`ifdef DEBUG
    assign debug_state = addr_latch;

`endif


// 现在让你设计一个FPGA的模块frequency_measure，模块接口如下
//     // 接口端口定义
//     input reset,              // 复位信号
//     input clk,                // 时钟信号
//     input en_read,// 使能读
//     output logic[15:0] module_out,
//     input  [15:0] module_in,
//     output logic notify,    // 通知线，表明模块数据已准备好

//     // ADC接口
//     input [11:0] ADC_DATA,  // ADC数据输入
//     output logic ADC_CLK, // ADC时钟输出
//     output logic ADC_OE,  // 低电平使能

//     // 触发模块接口
//     input trigger
// 当en_read拉低时，notify拉高，模块开始等待trigger拉高，如果1000个时钟周期内没有拉高或者trigger拉高，那么就开始准备读取ADC数据存入寄存器数组mem中，存满400个数据后，notify拉低，任务结束。
// ADC数据的采样是在ADC_CLK的上升沿，其中ADC_CLK和上升沿时刻我已经实现了，不需要写，其中start_adc为1，即表示上升沿到了，可以直接拿if(start_adc)为采样判断条件。
// 编写代码时要注意无论是always_comb还是always_ff块，一个信号不能被多个块同时驱动。编写代码要考虑到稳定性和高性能，并且编写代码时，每一行前面都要加一个Tab制表符

endmodule