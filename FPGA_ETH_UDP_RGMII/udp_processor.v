// ============================================================================
// Module: udp_processor
// Description: 处理 UDP 数据包的回环拷贝
// ============================================================================

module udp_processor #(
    parameter [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter [31:0] FPGA_IP = {8'd192, 8'd168, 8'd1, 8'd123},
    parameter [15:0] FPGA_UDP_PORT = 16'd1234
) (
    input wire clk,
    input wire rst_n,

    // 控制接口
    input  wire        work_en,
    input  wire [10:0] pkt_len_in,
    output reg         done,
    input  wire [31:0] dst_ip,
    input  wire [47:0] dst_mac,
    input  wire [15:0] dst_port,

    // RAM 接口
    output reg  [10:0] rx_ram_r_addr,
    input  wire [ 7:0] rx_ram_r_data,
    output reg  [10:0] tx_ram_w_addr,
    output reg  [ 7:0] tx_ram_w_data,
    output reg         tx_ram_w_en
);

  reg [10:0] cnt;
  reg [10:0] r_addr_ff;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt         <= 0;
      done        <= 0;
      tx_ram_w_en <= 0;
    end else if (work_en) begin
      rx_ram_r_addr <= cnt;
      r_addr_ff     <= rx_ram_r_addr;
      tx_ram_w_addr <= r_addr_ff;
      case (cnt)
        0 + 2:   tx_ram_w_data <= dst_mac[47:40];  // 目的MAC,指定填充
        1 + 2:   tx_ram_w_data <= dst_mac[39:32];
        2 + 2:   tx_ram_w_data <= dst_mac[31:24];
        3 + 2:   tx_ram_w_data <= dst_mac[23:16];
        4 + 2:   tx_ram_w_data <= dst_mac[15:8];
        5 + 2:   tx_ram_w_data <= dst_mac[7:0];
        6 + 2:   tx_ram_w_data <= FPGA_MAC[47:40];  // 源MAC
        7 + 2:   tx_ram_w_data <= FPGA_MAC[39:32];
        8 + 2:   tx_ram_w_data <= FPGA_MAC[31:24];
        9 + 2:   tx_ram_w_data <= FPGA_MAC[23:16];
        10 + 2:  tx_ram_w_data <= FPGA_MAC[15:8];
        11 + 2:  tx_ram_w_data <= FPGA_MAC[7:0];
        26 + 2:  tx_ram_w_data <= FPGA_IP[31:24];  // 源IP,指定填充
        27 + 2:  tx_ram_w_data <= FPGA_IP[23:16];
        28 + 2:  tx_ram_w_data <= FPGA_IP[15:8];
        29 + 2:  tx_ram_w_data <= FPGA_IP[7:0];
        30 + 2:  tx_ram_w_data <= dst_ip[31:24];  // UDP 目的IP
        31 + 2:  tx_ram_w_data <= dst_ip[23:16];  // UDP 目的IP
        32 + 2:  tx_ram_w_data <= dst_ip[15:8];  // UDP 目的IP
        33 + 2:  tx_ram_w_data <= dst_ip[7:0];  // UDP 目的IP;
        34 + 2:  tx_ram_w_data <= FPGA_UDP_PORT[15:8];  // UDP 源端口
        35 + 2:  tx_ram_w_data <= FPGA_UDP_PORT[7:0];  // UDP 源端口
        36 + 2:  tx_ram_w_data <= dst_port[15:8];  // UDP 目端口
        37 + 2:  tx_ram_w_data <= dst_port[7:0];  // UDP 目端口
        40 + 2:  tx_ram_w_data <= 8'h00;            // UDP 校验和设为 0
        41 + 2:  tx_ram_w_data <= 8'h00;
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
      cnt         <= 0;
      done        <= 0;
      tx_ram_w_en <= 0;
    end
  end
endmodule
