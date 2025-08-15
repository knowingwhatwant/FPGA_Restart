module Counter(input clk,
    input rst_n,
    input enable,
    output [3:0] count
    );
    

parameter COUNT_WIDTH = 4;

reg [COUNT_WIDTH-1:0] d_inputs;  // D触发器的输入
wire [COUNT_WIDTH-1:0] count_reg;  // 计数寄存器

// 例化4个D触发器
genvar i;
generate
    for (i = 0; i < COUNT_WIDTH; i = i + 1) begin : dff_gen
        dff1 dff_inst (
            .clk(clk),
            .rst_n(rst_n),
            .d(d_inputs[i]),
            .q(count_reg[i])
        );
    end
    endgenerate 

// 组合逻辑：计算下一个计数值
always @(*) begin
    if (!rst_n) begin
        d_inputs = 4'b0000;  
    end else if (enable) begin
        d_inputs = count_reg + 1'b1;  
    end else begin
        d_inputs = count_reg;
    end
end

assign count = count_reg;

endmodule