`timescale 1ns / 1ns

module decode3_8_tb();
    reg [2:0] in;
    wire [7:0] y;
    decode3_8 uut (.in(in), .y(y));

    initial begin


        in = 3'b000; #200;
        in = 3'b001; #200;
        in = 3'b010; #200;
        in = 3'b011; #200;
        in = 3'b100; #200;
        in = 3'b101; #200;
        in = 3'b110; #200;
        in = 3'b111; #200;
        $stop;
    end



endmodule