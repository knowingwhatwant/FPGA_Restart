`timescale 1ns/1ps
module Uart_tx_data_tb();



	reg clk;
    reg rst_n;
    reg [39:0] Data40;
    reg trans_go;
    wire uart_tx;
    wire trans_done;


Uart_tx_data uart_tx_data_inst(
    clk,
    rst_n,
    Data40,
    trans_go,
    uart_tx,
    trans_done
);

    initial clk = 1;
    always #10 clk = ~clk; // 50MHz clock

    initial begin 
        rst_n = 0;
        Data40 = 40'h0;
        trans_go = 0;
        #201;
        rst_n = 1;
        #200;
        Data40 = 40'h123456789A;
        trans_go = 1;
        #20
        trans_go = 0;
        @(posedge trans_done);
        #2000;
        
        Data40 = 40'h123456789A;
        trans_go = 1;
        #20
        trans_go = 0;
        @(posedge trans_done);
        #2000;
        $stop;
end
endmodule