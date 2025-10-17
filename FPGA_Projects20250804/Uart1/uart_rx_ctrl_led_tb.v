`timescale 1ns/1ps

module uart_rx_ctrl_led_tb();


    reg clk;
    reg rst_n;
    reg uart_rx;
    wire led_out;

    uart_rx_ctrl_led uut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .led_out(led_out)
    );

    initial clk = 0;
    always #10 clk = ~clk; // 50MHz clock

    initial begin 
        rst_n = 0;
        uart_rx = 1; // Idle state
        #201;
        rst_n = 1;
        #200;
        uart_tx_byte(8'h55); // Transmit 0x55
        #90000;
        uart_tx_byte(8'hA5); // Transmit 0xA5
        #90000;
        uart_tx_byte(8'h12);
        #90000;
        uart_tx_byte(8'h23);
        #90000;
        uart_tx_byte(8'h56);
        #90000;
        uart_tx_byte(8'h78);
        #90000;
        uart_tx_byte(8'h9A); // Transmit control byte
        #90000;
        uart_tx_byte(8'hF0); // Transmit 0xF0
        #900000;
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