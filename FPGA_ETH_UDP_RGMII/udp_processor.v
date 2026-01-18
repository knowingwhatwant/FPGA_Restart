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
            tx_ram_w_data <= rx_ram_r_data; // 此处可进行 MAC/IP 交换逻辑

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