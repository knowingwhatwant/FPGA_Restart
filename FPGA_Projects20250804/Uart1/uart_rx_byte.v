module uart_rx_byte(
    input clk,
    input rst_n,
    input uart_rx,
    input [2:0] baud_set,
    output reg [7:0] byte_out,
    output reg rx_done
)

    // 边沿检测
    reg [1:0] uart_rx_r;
    always@(posedge clk) begin
            uart_rx_r[0] <= uart_rx;
            uart_rx_r[1] <= uart_rx_r[0];
        end
    end
    // 边沿检测，输出脉冲信号
    wire pedge_uart_rxl; // 检测到下降沿
    assign pedge_uart_rxl = (uart_rx_r[1] == 1'b0) && (uart_rx_r[0] == 1'b1);

    wire nedge_uart_rxl; // 检测到上升沿
    assign nedge_uart_rxl = (uart_rx_r[1] == 1'b1) && (uart_rx_r[0] == 1'b0);

    // 对数据进行采样，1bit分16个采样点，舍弃前5后4，取中7点
    // 采样点周期（速率）
    reg [8:0] Bps_DR;
    always@(*) begin
        case(baud_set)
        3'b000: Bps_DR = 1000000000/300/20/16-1;    // 1/300 second in clock cycles at 50MHz
        3'b001: Bps_DR = 1000000000/1200/20/16-1;   // 1/1200 second in clock cycles at 50MHz
        3'b010: Bps_DR = 1000000000/2400/20/16-1;   // 1/2400 second in clock cycles at 50MHz
        3'b011: Bps_DR = 1000000000/4800/20/16-1;   // 1/4800 second in clock cycles at 50MHz
        3'b100: Bps_DR = 1000000000/9600/20/16-1;   // 1/9600 second in clock cycles at 50MHz
        3'b101: Bps_DR = 1000000000/19200/20/16-1;  // 1/19200 second in clock cycles at 50MHz
        3'b110: Bps_DR = 1000000000/115200/20/16-1; // 1/115200 second in clock cycles at 50MHz
        default: Bps_DR =1000000000/115200/20/16-1; // Default to 1/115200 second in clock cycles at 50MHz
        endcase
    end

    wire bps_clk_16x;
    assign bps_clk_16x = (clk_div_16x = Bps_DR / 2);  // 采样点在周期中间
    reg [8:0] clk_div_16x;
    // 脉冲信号转电平信号
    reg RX_EN;
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            RX_EN <= 0;
        end else if(pedge_uart_rxl) 
            RX_EN <= 1;
        end else if(rx_done || (sta_bit >= 4))begin
            RX_EN <= 0;
        end
    end

    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            clk_div_16x <= 0;
        end else if(RX_EN) begin
            if(clk_div_16x == Bps_DR) begin
                clk_div_16x <= 0;
            end else begin
                clk_div_16x <= clk_div_16x + 1'b1;
            end
        end else begin
            clk_div_16x <= 0;
        end
    end



    reg [7:0] bps_cnt;   // 一共160个采样点
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            bps_cnt <= 0;
        end else if(bps_clk_16x) begin
            if(bps_cnt == 160) begin
                bps_cnt <= 0;
            end else begin
                bps_cnt <= bps_cnt + 1'b1;
            end
            else 
                bps_cnt <= bps_cnt;
    end


    reg [2:0] r_data[7:0]; // 3位，10个
    reg [2:0] sta_bit;
    reg [2:0] sto_bit;
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            sta_bit <= 0;
            sto_bit <= 0;
            r_data[0] <= 0;
            r_data[1] <= 0;
            r_data[2] <= 0;
            r_data[3] <= 0;
            r_data[4] <= 0;
            r_data[5] <= 0;
            r_data[6] <= 0;
            r_data[7] <= 0;
        end
        else if(bps_clk_16x)begin
            case(bps_cnt)
                5,6,7,8,9,10,11: sta_bit <= sta_bit + uart_rx; // 起始位采样
                21,22,23,24,25,26,27: r_data[0] <= r_data[0] + uart_rx; // 数据位0采样
                37,38,39,40,41,42,43: r_data[1] <= r_data[1] + uart_rx; // 数据位1采样
                53,54,55,56,57,58,59: r_data[2] <= r_data[2] + uart_rx; // 数据位2采样
                69,70,71,72,73,74,75: r_data[3] <= r_data[3] + uart_rx; // 数据位3采样
                85,86,87,88,89,90,91: r_data[4] <= r_data[4] + uart_rx; // 数据位4采样
                101,102,103,104,105,106,107: r_data[5] <= r_data[5] + uart_rx; // 数据位5采样
                117,118,119,120,121,122,123: r_data[6] <= r_data[6] + uart_rx; // 数据位6采样
                133,134,135,136,137,138,139: r_data[7] <= r_data[7] + uart_rx; // 数据位7采样
                149,150,151,152,153,154,155: sto_bit <= sto_bit + uart_rx; // 停止位采样
                default: ;
        end
    end

     always@(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            byte_out <= 0;
        end
        else if(bps_clk_16x && (bps_cnt == 159)) begin
            byte_out[0] <= (r_data[0] > 4) ? 1'b1 : 1'b0;
            byte_out[1] <= (r_data[1] > 4) ? 1'b1 : 1'b0;
            byte_out[2] <= (r_data[2] > 4) ? 1'b1 : 1'b0;
            byte_out[3] <= (r_data[3] > 4) ? 1'b1 : 1'b0;
            byte_out[4] <= (r_data[4] > 4) ? 1'b1 : 1'b0;
            byte_out[5] <= (r_data[5] > 4) ? 1'b1 : 1'b0;
            byte_out[6] <= (r_data[6] > 4) ? 1'b1 : 1'b0;
            byte_out[7] <= (r_data[7] > 4) ? 1'b1 : 1'b0;
        end 
     end
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            rx_done <= 0;
        end
        else if(bps_clk_16x && (bps_cnt == 159)) 
            rx_done <= 1'b1;
        else 
            rx_done <= 1'b0;
      



endmodule