module smg_disp_de115(
    input clk,
    output reg [6:0] smg_out

);

    always @(posedge clk) begin
        smg_out <= 8'h82;
    end


endmodule