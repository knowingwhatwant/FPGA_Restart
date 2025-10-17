`timescale 1ns/1ps

module uart_rx_byte_tb(); 
        reg clk;
        reg rst_n;
        reg uart_rx;
        reg [2:0] baud_set;
        wire [7:0] byte_out;
        wire rx_done;

    uart_rx_byte uut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .baud_set(baud_set),
        .byte_out(byte_out),
        .rx_done(rx_done)
    );

        initial clk = 0;
        always #10 clk = ~clk; // 50MHz clock

        initial begin 
            rst_n = 0;
            baud_set = 3'b110; // 115200 baud
            uart_rx = 1; // Idle state
            #201;
            rst_n = 1;
            #200;
            uart_tx_byte(8'hEE); // Transmit 0xA5
            
            #90000;
            uart_tx_byte(8'hFF); // Transmit 0x5A
            
            #90000;
            uart_tx_byte(8'hAA); // Transmit 0xAA
           
            #90000;
            $stop;
        end

        task uart_tx_byte;
            input [7:0] tx_data;
            begin
                uart_rx = 1; // Idle state
                #20;
                uart_rx = 0;
                #8680; // Start bit duration for 115200 baud
                uart_rx = tx_data[0];
                #8680;
                uart_rx = tx_data[1];
                #8680;
                uart_rx = tx_data[2];
                #8680;
                uart_rx = tx_data[3];
                #8680;
                uart_rx = tx_data[4];
                #8680;
                uart_rx = tx_data[5];
                #8680;
                uart_rx = tx_data[6];
                #8680;
                uart_rx = tx_data[7];
                #8680;
                uart_rx = 1;
                #8680; // Stop bit duration
                uart_rx = 1; // Idle state
            end
        endtask



endmodule