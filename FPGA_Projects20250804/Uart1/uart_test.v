module uart_test(
    input clk,
    input rst_n,
    input [7:0] byte_in,
    input [2:0] baud_set,
    input send_en,
    output uart_tx,
    output uart_tx_done
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
        3'b000: Baud_cnt = 1/300*1000000000/20; // 1/300 second in clock cycles at 50MHz
        3'b001: Baud_cnt = 1/1200*1000000000/20; // 1/1200 second in clock cycles at 50MHz
        3'b010: Baud_cnt = 1/2400*1000000000/20; // 1/2400 second in clock cycles at 50MHz
        3'b011: Baud_cnt = 1/4800*1000000000/20; // 1/4800 second in clock cycles at 50MHz
        3'b100: Baud_cnt = 1/9600*1000000000/20; // 1/9600 second in clock cycles at 50MHz
        3'b101: Baud_cnt = 1/19200*1000000000/20; // 1/19200 second in clock cycles at 50MHz
        3'b110: Baud_cnt = 1/115200*1000000000/20; // 1/115200 second in clock cycles at 50MHz
        default: Baud_cnt = 1/115200*1000000000/20; // Default to 1/115200 second in clock cycles at 50MHz
        endcase
    end


    // 波特率计时器
    reg [20:0] clk_div;

    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clk_div <= 0;
        end else if(clk_div == Baud_cnt-1) begin
            clk_div <= 0;
        end else begin
            clk_div <= clk_div + 1;
        end
    end

    // 发送时序控制
    reg [3:0] bps_cnt; //状态指示，一共10个状态，
    always@(posedge clk or negedge rst_n) begin 
        if(!rst_n) begin
            bps_cnt <= 0;
        end else if (send_en) begin // 使能够开始遍历发送状态
            if(clk_div == 1) begin // 仅在波特率计时器到达时才增加状态计数
                if(bps_cnt == 12) begin
                    bps_cnt <= 0;
                end else begin
                    bps_cnt <= bps_cnt + 1;
                end
            end else begin          // 0是idle状态
            bps_cnt <= 0;
            end
        end
    end




    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            uart_tx <= 1; // idle state
            uart_tx_done <= 0;
        end else if (send_en)begin
            case(bps_cnt) 
            1: uart_tx <= 0; // start bit
            2: uart_tx <= byte_in[0];
            3: uart_tx <= byte_in[1];
            4: uart_tx <= byte_in[2];
            5: uart_tx <= byte_in[3];
            6: uart_tx <= byte_in[4];
            7: uart_tx <= byte_in[5];
            8: uart_tx <= byte_in[6];
            9: uart_tx <= byte_in[7];
            10: uart_tx <= 1; // stop bit
            11: begin uart_tx <= 1; uart_tx_done <= 1; end // ensure stop bit is stable before marking done
            default: uart_tx <= 1; // idle state
            endcase
        end else begin
            bps_cnt <= 0;
            uart_tx <= 1; // idle state
        end     
    end




endmodule