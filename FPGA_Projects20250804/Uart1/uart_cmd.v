`timescale 1ns/1ps
module uart_cmd(
    input clk,
    input rst_n,
    input rx_done,
    input [7:0] rx_data,
    output reg[7:0] ctrl,
    output reg[31:0] time_set
);

    reg [7:0] data_str [7:0];

    always @(posedge clk)
    if (rx_done) begin 
        data_str[7] <= #1 rx_data;
        data_str[6] <= #1 data_str[7];
        data_str[5] <= #1 data_str[6];
        data_str[4] <= #1 data_str[5];
        data_str[3] <= #1 data_str[4];
        data_str[2] <= #1 data_str[3];
        data_str[1] <= #1 data_str[2];
        data_str[0] <= #1 data_str[1];
	end


    reg r_rx_done;
    always @(posedge clk)
        r_rx_done <= rx_done;

    always@(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl <= 0;
            time_set <= 0;
        end else if (r_rx_done) begin         // 接收到新数据才判断
            if ((data_str[0] == 8'h55)&&(data_str[1]==8'hA5) &&(data_str[7]==8'hF0))
				begin
                time_set <= #1 {data_str[5],data_str[4],data_str[3],data_str[2]};
                ctrl <= #1 data_str[6];
                end
            end
    end


endmodule

