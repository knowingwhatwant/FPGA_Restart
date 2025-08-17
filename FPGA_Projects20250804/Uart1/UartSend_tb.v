`timescale 1ns/1ps

module UartSend_tb();

    reg clk;
    reg rst_n;
    wire  uart_tx;


    UartSend UartSend_inst (
        .clk(clk),
        .rst_n(rst_n),
        .uart_tx(uart_tx)
    );


    initial clk = 1;
    always #10 clk = ~clk; // 50MHz clock

    initial begin
        rst_n = 0;
        #201;
        rst_n = 1;
        #100;
        // Start sending data
        #50000000;
        $stop; // Stop simulation after some time
    end


	 




endmodule