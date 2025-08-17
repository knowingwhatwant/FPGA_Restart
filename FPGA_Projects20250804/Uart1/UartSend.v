module UartSend(
    input clk,
    input rst_n,
    output  uart_tx
);

    // 中间信号
    
    wire uart_tx_done;


    parameter BUAD_SET = 3'h6; // Default to 115200 baud
    parameter CNT_10MS = 19'd500000; // 10ms counter at 50MHz clock

    reg [18:0]cnt;
    reg [7:0] data_send_cnt ;   // 递增数据
    reg send_go;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            cnt <= 0;
        end else if(cnt ==  CNT_10MS-1) begin
            cnt <= 0;
        end else begin
            cnt <= cnt + 1'b1;
        end
        
    end

    // 单脉冲发送指示新厚爱
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            send_go <= 0;
        end else if(cnt == 1)begin
            send_go <= 1; // Enable sending every 10ms
        end else begin
            send_go <= 0; 
        end
    end


     always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            data_send_cnt <= 0;
        end else if(uart_tx_done==1) 
        begin
            data_send_cnt <= data_send_cnt + 1'b1;
        end
        
     end

    uart_tx_byte uart_tx_byte_inst2 (
        .clk(clk),
        .rst_n(rst_n),
        .byte_in(data_send_cnt),
        .send_go(send_go),
        .baud_set(BUAD_SET),
        .uart_tx(uart_tx),
        .uart_tx_done(uart_tx_done)
    );






endmodule