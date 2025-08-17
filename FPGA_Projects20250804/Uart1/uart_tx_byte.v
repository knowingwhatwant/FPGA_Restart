module uart_tx_byte(
    input clk,
    input rst_n,
    input [7:0] byte_in,
    input [2:0] baud_set,
    input send_go,
    output  reg uart_tx,
    output  reg uart_tx_done
);





    // 波特率设置
    // 0: 300 baud
    // 1: 1200 baud
    // 2: 2400 baud
    // 3: 4800 baud
    // 4: 9600 baud
    // 5: 19200 baud
    // 6: 115200 baud


    reg [20:0] Baud_cnt;

    // 1/300*1000000000/20= 1666666; // 1/300 second in clock cycles at 50MHz
    always@(*) begin
        case(baud_set)
        3'b000: Baud_cnt = 1000000000/300/20; // 1/300 second in clock cycles at 50MHz
        3'b001: Baud_cnt = 1000000000/1200/20; // 1/1200 second in clock cycles at 50MHz
        3'b010: Baud_cnt = 1000000000/2400/20; // 1/2400 second in clock cycles at 50MHz
        3'b011: Baud_cnt = 1000000000/4800/20; // 1/4800 second in clock cycles at 50MHz
        3'b100: Baud_cnt = 1000000000/9600/20; // 1/9600 second in clock cycles at 50MHz
        3'b101: Baud_cnt = 1000000000/19200/20; // 1/19200 second in clock cycles at 50MHz
        3'b110: Baud_cnt = 1000000000/115200/20; // 1/115200 second in clock cycles at 50MHz
        default: Baud_cnt =1000000000/115200/20; // Default to 1/115200 second in clock cycles at 50MHz
        endcase
    end

    reg send_en;
    // 波特率计时器
    reg [20:0] clk_div;

    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clk_div <= 0;
        end else if(send_en) begin
            if(clk_div == Baud_cnt-1) begin
                clk_div <= 0;
            end else begin
                clk_div <= clk_div + 1'b1;
            end
        end else begin
            clk_div <= 0;
        end

    end

    wire bps_clk;
    assign bps_clk = (clk_div == 1);

    // 发送时序控制
    reg [3:0] bps_cnt; //状态指示，一共10个状态，
    always@(posedge clk or negedge rst_n) begin 
        if(!rst_n) 
        begin
            bps_cnt <= 0;
        end 
        else if (send_en) 
        begin // 使能够开始遍历发送状态
            if(bps_clk) 
            begin
                if(bps_cnt == 11) begin
                    bps_cnt <= 0;
                end else 
                    bps_cnt <= bps_cnt + 1'b1;
            end    
        end else begin          // 0是idle状态
            bps_cnt <= 0;
        end 
    end

    
	 
    // send_en 使能由
    always@(posedge clk) begin
        if(rst_n == 0)
            send_en <= 0;
        else if(send_go)
            send_en <= 1;
        else if(uart_tx_done)
            send_en <= 0;
        end

    reg [7:0] r_data_byte;
    always@(posedge clk) begin
        if(send_go)
            r_data_byte <= byte_in;
        else 
            r_data_byte <= r_data_byte;
    end


    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            uart_tx <= 1; // idle state

        end else begin
            case(bps_cnt) 
            1: uart_tx <= 0;
            2: uart_tx <= r_data_byte[0];
            3: uart_tx <= r_data_byte[1];
            4: uart_tx <= r_data_byte[2];
            5: uart_tx <= r_data_byte[3];
            6: uart_tx <= r_data_byte[4];
            7: uart_tx <= r_data_byte[5];
            8: uart_tx <= r_data_byte[6];
            9: uart_tx <= r_data_byte[7];
            10: uart_tx <= 1; // stop bit
            11: uart_tx <= 1;  // ensure stop bit is stable before marking done
            default: uart_tx <= 1;// idle state
            endcase
        end  
    end
     always@(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            uart_tx_done <= 0;
        else if((bps_cnt == 10)&& (clk_div==1))
            uart_tx_done <= 1; // Set done signal when stop bit is sent
        else
            uart_tx_done <= 0; // Reset done signal when in idle state
  
	end

endmodule