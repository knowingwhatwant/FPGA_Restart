`timescale 1ns / 1ps
module key_filter_tb2;

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
        press_key(2);
        $stop;
    end


    reg [31:0] rand;

    task press_key;
        input [3:0] seed;
        begin
            #20000000;
            repeat(5) begin
            rand = {$random} % 10000000;   //0~10ms随机间隔
            #rand key =~ key;
            end
            key = 0;
            #40000000;
            repeat(5) begin
            rand = {$random} % 10000000;   //0~10ms随机间隔
            #rand key =~ key;
            end
            key = 1;
            #40000000;
        end
    endtask

endmodule