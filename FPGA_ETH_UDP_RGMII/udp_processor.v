// ============================================================================
// Module: udp_processor
// Description: 处理 UDP 数据包的回环拷贝
// ============================================================================

module udp_processor (
    input  wire        clk,
    input  wire        rst_n,

    // 控制接口
    input  wire        work_en,
    input  wire [10:0] pkt_len_in,
    output reg         done,
    input  wire [15:0] word6,
    input  wire [15:0] word7,
    input  wire [15:0] word8,
    input  wire [15:0] word9,
    // RAM 接口
    output reg  [10:0] rx_ram_r_addr,
    input  wire [7:0]  rx_ram_r_data,
    output reg  [10:0] tx_ram_w_addr,
    output reg  [7:0]  tx_ram_w_data,
    output reg         tx_ram_w_en
);

    reg [10:0] cnt;
    reg [10:0] r_addr_ff;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0; done <= 0; tx_ram_w_en <= 0;
        end else if (work_en) begin
            rx_ram_r_addr <= cnt;
            r_addr_ff     <= rx_ram_r_addr;
            tx_ram_w_addr <= r_addr_ff;
            case (cnt) 
                26+2: tx_ram_w_data <= word6[15:8]; // UDP 源IP
                27+2: tx_ram_w_data <= word6[7:0];  // UDP 源IP
                28+2: tx_ram_w_data <= word7[15:8]; // UDP 源IP
                29+2: tx_ram_w_data <= word7[7:0];  // UDP 源IP
                30+2: tx_ram_w_data <= word8[15:8]; // UDP 目的IP
                31+2: tx_ram_w_data <= word8[7:0];  // UDP 目的IP
                32+2: tx_ram_w_data <= word9[15:8]; // UDP 目的IP
                33+2: tx_ram_w_data <= word9[7:0];  // UDP 目的IP
                default: tx_ram_w_data <= rx_ram_r_data;
            endcase
            // 开启写使能 (考虑流水线延迟)
            if (cnt > 0 && cnt <= pkt_len_in + 1) tx_ram_w_en <= 1;
            else tx_ram_w_en <= 0;

            if (cnt < pkt_len_in + 2) cnt <= cnt + 1;
            else begin
                done <= 1;
                cnt  <= 0;
            end
        end else begin
            cnt <= 0; done <= 0; tx_ram_w_en <= 0;
        end
    end
endmodule