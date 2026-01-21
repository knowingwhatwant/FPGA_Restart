// ============================================================================
// Module: arp_processor
// Description: 处理 ARP 响应包的生成。
// 逻辑：直接利用嗅探到的对方 MAC/IP，在 tx_ram 中填入标准的 42 字节 ARP 回复报文。
// ============================================================================

module arp_processor #(
    parameter [47:0] FPGA_MAC = 48'h02_00_00_00_00_01,
    parameter [31:0] FPGA_IP = {8'd192, 8'd168, 8'd1, 8'd123}
)(
    input  wire        clk,
    input  wire        rst_n,
    

    input  wire [47:0] rem_mac_in,     // 顶层嗅探到的对方 MAC
    input  wire [31:0] rem_ip_in,      // 顶层嗅探到的对方 IP

    // 控制接口
    input  wire        work_en,        // 模块使能（来自状态机 S_WORK 阶段）
    output reg         done,           // 构造完成标志

    // TX RAM 写入接口 (用于存放生成的回复包)
    output reg  [10:0] tx_ram_w_addr,
    output reg  [7:0]  tx_ram_w_data,
    output reg         tx_ram_w_en
);

    reg [5:0] cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
            done <= 0;
            tx_ram_w_en <= 0;
            tx_ram_w_addr <= 0;
            tx_ram_w_data <= 0;
        end else if (work_en) begin
            if (cnt <= 6'd41) begin
                tx_ram_w_en   <= 1'b1;
                tx_ram_w_addr <= {5'b0, cnt};
                
                // --- 构造 42 字节标准 ARP Reply 报文 ---
                case (cnt)
                    // 以太网报头 (14 字节)
                    6'd0 : tx_ram_w_data <= rem_mac_in[47:40]; // 目的 MAC (电脑)
                    6'd1 : tx_ram_w_data <= rem_mac_in[39:32];
                    6'd2 : tx_ram_w_data <= rem_mac_in[31:24];
                    6'd3 : tx_ram_w_data <= rem_mac_in[23:16];
                    6'd4 : tx_ram_w_data <= rem_mac_in[15: 8];
                    6'd5 : tx_ram_w_data <= rem_mac_in[ 7: 0];
                    6'd6 : tx_ram_w_data <= FPGA_MAC[47:40]; // 源 MAC (FPGA)
                    6'd7 : tx_ram_w_data <= FPGA_MAC[39:32];
                    6'd8 : tx_ram_w_data <= FPGA_MAC[31:24];
                    6'd9 : tx_ram_w_data <= FPGA_MAC[23:16];
                    6'd10: tx_ram_w_data <= FPGA_MAC[15: 8];
                    6'd11: tx_ram_w_data <= FPGA_MAC[ 7: 0];
                    6'd12: tx_ram_w_data <= 8'h08;            // 类型: ARP (0x0806)
                    6'd13: tx_ram_w_data <= 8'h06;
                    
                    // ARP 净荷 (28 字节)
                    6'd14: tx_ram_w_data <= 8'h00;            // 硬件类型: 以太网 (1)
                    6'd15: tx_ram_w_data <= 8'h01;
                    6'd16: tx_ram_w_data <= 8'h08;            // 协议类型: IPv4 (0x0800)
                    6'd17: tx_ram_w_data <= 8'h00;
                    6'd18: tx_ram_w_data <= 8'h06;            // MAC 长度: 6
                    6'd19: tx_ram_w_data <= 8'h04;            // IP 长度: 4
                    6'd20: tx_ram_w_data <= 8'h00;            // 操作码: Reply (2)
                    6'd21: tx_ram_w_data <= 8'h02;
                    6'd22: tx_ram_w_data <= FPGA_MAC[47:40]; // 发送方 MAC (FPGA)
                    6'd23: tx_ram_w_data <= FPGA_MAC[39:32];
                    6'd24: tx_ram_w_data <= FPGA_MAC[31:24];
                    6'd25: tx_ram_w_data <= FPGA_MAC[23:16];
                    6'd26: tx_ram_w_data <= FPGA_MAC[15: 8];
                    6'd27: tx_ram_w_data <= FPGA_MAC[ 7: 0];
                    6'd28: tx_ram_w_data <= FPGA_IP [31:24]; // 发送方 IP (FPGA)
                    6'd29: tx_ram_w_data <= FPGA_IP [23:16];
                    6'd30: tx_ram_w_data <= FPGA_IP [15: 8];
                    6'd31: tx_ram_w_data <= FPGA_IP [ 7: 0];
                    6'd32: tx_ram_w_data <= rem_mac_in[47:40]; // 目标 MAC (电脑)
                    6'd33: tx_ram_w_data <= rem_mac_in[39:32];
                    6'd34: tx_ram_w_data <= rem_mac_in[31:24];
                    6'd35: tx_ram_w_data <= rem_mac_in[23:16];
                    6'd36: tx_ram_w_data <= rem_mac_in[15: 8];
                    6'd37: tx_ram_w_data <= rem_mac_in[ 7: 0];
                    6'd38: tx_ram_w_data <= rem_ip_in [31:24]; // 目标 IP (电脑)
                    6'd39: tx_ram_w_data <= rem_ip_in [23:16];
                    6'd40: tx_ram_w_data <= rem_ip_in [15: 8];
                    6'd41: tx_ram_w_data <= rem_ip_in [ 7: 0];
                    default: tx_ram_w_data <= 8'h00;
                endcase
                cnt <= cnt + 1'b1;
            end else begin
                tx_ram_w_en <= 1'b0;
                done <= 1'b1;
            end
        end else begin
            cnt <= 0;
            done <= 0;
            tx_ram_w_en <= 0;
        end
    end
endmodule