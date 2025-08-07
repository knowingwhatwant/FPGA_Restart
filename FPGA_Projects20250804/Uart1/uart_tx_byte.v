module uart_tx_byte(
    input  clk,
    input  rst_n,
    input  [7:0] byte_in,
    input  Send_en,
    input  [2:0] Buad_set,
    output reg uart_tx,
    output reg Send_done
);
    reg [17:0] bps_DR;
    


    // Baud_set = 0: 9600
    // Baud_set = 1: 19200
    // Baud_set = 2: 38400
    // Baud_set = 3: 57600
    // Baud_set = 4: 115200

    always@(*)
    begin
        case(Buad_set) //@50Mhz
            3'b000: bps_DR = 1000000000/9600/20;     // 9600 baud rate(1e9 / 9600)
            3'b001: bps_DR = 1000000000/19200/20;    // 19200 baud rate
            3'b010: bps_DR = 1000000000/38400/20;    // 38400 baud rate
            3'b011: bps_DR = 1000000000/57600/20;    // 57600 baud rate
            3'b100: bps_DR = 1000000000/115200/20;   // 115200 baud rate
            default: bps_DR = 1000000000/9600/20;    // Default to 9600
        endcase
    end

    reg [17:0] clk_div;
    always@(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
            clk_div <= 0;
        else if(Send_en) begin
            if(clk_div == bps_DR-1)
                clk_div <= 0;
            else
            clk_div <= clk_div + 1;
        end
        else clk_div <= 0;
    end
    
    // 发送状态控制
    reg [3:0] bps_cnt;
    always@(posedge clk or negedge rst_n)
    begin
        if(!rst_n)
            bps_cnt <= 0;
        else if(clk_div == bps_DR-1) begin
            if(bps_cnt == 12)
            bps_cnt <= 0;
            else 
            bps_cnt <= bps_cnt + 1'b1;
        end
    end

    always@(posedge clk or negedge rst_n)
    begin
        if(!rst_n) begin
            uart_tx <= 1;
            Send_done <= 0;
			end
        else begin
            case(bps_cnt) 
            1: begin uart_tx <= 0; Send_done <= 0; end
            2: uart_tx <= byte_in[0]; 
            3: uart_tx <= byte_in[1]; 
            4: uart_tx <= byte_in[2]; 
            5: uart_tx <= byte_in[3]; 
            6: uart_tx <= byte_in[4]; 
            7: uart_tx <= byte_in[5]; 
            8: uart_tx <= byte_in[6]; 
            9: uart_tx <= byte_in[7]; 
            10: uart_tx <= 1; 
            11: begin uart_tx <= 1;   Send_done <= 1; end
            default: uart_tx <= 1;
            endcase
        end
    end



endmodule
