module Uart_tx_data(
    input clk,
    input rst_n,
    input [39:0] Data40,
    input trans_go,
    output  uart_tx,
    output  reg trans_done
);

    // 中间信号
    parameter BUAD_SET = 3'h6; // Default to 115200 baud
    wire uart_tx_done;

    reg [7:0] data_byte;
    reg send_go;
    reg [2:0]state;


    uart_tx_byte uart_tx_byte_inst3 (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(data_byte),
        .send_go(send_go),
        .baud_set(BUAD_SET),
        .uart_tx(uart_tx),
        .uart_tx_done(uart_tx_done)
    );

    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= 0;
            data_byte <= 0;
            send_go <= 0;
            trans_done <= 0;
        end else begin
            case(state)
                0: begin
                    trans_done <= 0;
                    if(trans_go) begin
                        state <= 1;
                        data_byte <= Data40[7:0];
                        send_go <= 1;
                    end
                    else begin
                        send_go <= 0;
                        state <= 0;
                end
                end
                1: begin
                    if(uart_tx_done) begin
                        data_byte <= Data40[15:8];
                        send_go <= 1;
                        state <= 2;
                    end
                    else begin
                        send_go <= 0;
                        state <= 1;
                    end
                end
                2: begin
                    if(uart_tx_done) begin
                        data_byte <= Data40[23:16];
                        send_go <= 1;
                        state <= 3;
                    end
                    else begin
                        send_go <= 0;
                        state <= 2;
                    end
                end
                3: begin
                    if(uart_tx_done) begin
                        data_byte <= Data40[31:24];
                        send_go <= 1;
                        state <= 4;
                    end
                    else begin
                        send_go <= 0;
                        state <= 3;
                    end
                end
                4: begin
                    if(uart_tx_done) begin
                        data_byte <= Data40[39:32];
                        send_go <= 1;
                        state <= 5;
                    end
                    else begin
                        send_go <= 0;
                        state <= 4;
                    end
                end
                5: begin
                    if(uart_tx_done) begin
                        state <= 0;
                        send_go <= 0;
                        trans_done <= 1;
                    end
                    else begin
                        send_go <= 0;
                        state <= 5;
                    end
                end
			endcase
        end
	end
	 
endmodule