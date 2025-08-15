`timescale 1ns / 1ps

module uart_tx_byte_tb();

    reg clk;
    reg rst_n;
    reg [7:0] byte_in;
    reg send_en;
    reg [2:0] Baud_set;
    wire uart_tx;
    wire uart_tx_done;

    uart_tx_byte uut (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(byte_in),
        .send_en(send_en),
        .baud_set(Baud_set),
        .uart_tx(uart_tx),
        .uart_tx_done(uart_tx_done)
    );
    initial clk = 1;
    always #10 clk = ~clk;

    initial begin
        rst_n = 0;
        byte_in = 0;
        send_en = 0;
        Baud_set = 3'b110; // Set baud rate to 115200
        #201;
        rst_n = 1; // Release reset
        #100;
        byte_in = 8'b10101010;
        send_en = 1; // Start sending
        #20;
        @(posedge uart_tx_done); // Wait for send done
		  send_en = 0;
        #2000;
		  byte_in = 8'b10101010;
        send_en = 1; // Start sending
        #20;
        @(posedge uart_tx_done); // Wait for send done  
		  send_en = 0;
		  #200;
        $stop;


    end






endmodule