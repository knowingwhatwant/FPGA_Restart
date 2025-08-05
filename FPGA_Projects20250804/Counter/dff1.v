// D触发器模块
module dff1 (
    input clk,
    input rst_n,
    input d,
    output reg q
);
    // D触发器实现
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= 1'b0;
        end else begin
            q <= d;
        end
    end
endmodule