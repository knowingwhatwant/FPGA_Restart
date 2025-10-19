`timescale 1ns / 1ps
module key_filter_tb;

    reg clk;
    reg rst_n;
    reg key;
    wire key_flag;

    wire key_state;

    key_filter key_filter_uut (
    .clk(clk),
    .rst_n(rst_n),
    .key(key),
    .key_flag(key_flag),
    .key_state(key_state)
);

    initial clk = 1;
    always #10 clk = ~clk; // 50MHz clock

    initial begin
        rst_n = 0;
        key = 1;
        #201;
        rst_n = 1; // Release reset
        #3000;
        key = 0;
        #20000; // Hold key low for 20ms
        key = 1;
        #30000;
        key = 0;
        #20000; // Hold key low for 20ms
        key = 1;
        #30000;
        key = 0;
        #50000000;

        key = 1;
        #20000; // Hold key low for 20ms
        key = 0;
        #30000;
        key = 1;
        #20000; // Hold key low for 20ms
        key = 0;
        #30000;
        key = 1;
        #50000000;
        $stop;
    end





endmodule