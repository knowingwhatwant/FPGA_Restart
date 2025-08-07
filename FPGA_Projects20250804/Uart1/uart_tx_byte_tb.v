`timescale 1ns / 1ps

module uart_tx_byte_tb();

    reg clk;
    reg rst_n;
    reg [7:0] byte_in;
    reg Send_en;
    reg [2:0] Buad_set;
    wire uart_tx;
    wire Send_done;

    uart_tx_byte uut (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(byte_in),
        .Send_en(Send_en),
        .Buad_set(Buad_set),
        .uart_tx(uart_tx),
        .Send_done(Send_done)
    );
    initial clk = 1;
    always #5 clk = ~clk;

    initial begin
        rst_n = 0;
        byte_in = 0;
        Send_en = 0;
        Buad_set = 3'b100; // Set baud rate to 115200
        #201;
        rst_n = 1; // Release reset
        #100;
        byte_in = 8'b10101010;
        Send_en = 1; // Start sending
        #20;
        @(posedge Send_done); // Wait for send done
        #200000;
        $stop;


    end






endmodule