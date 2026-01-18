// ============================================================================
// Module: tse_packet_processor
// Description: 顶层协议分发与调度中心。
// 修复点：
// 1. 关键修复：修正了 sniffing（嗅探）偏移量。
//    由于 SOP 拍在 IDLE 中处理，S_RX 的第一拍计数器为 1 对应的是包的第 2 字节。
//    因此 Type 字段 (13,14字节) 对应的计数器应为 12, 13。
// 2. 增强了状态机跳转的稳定性。
// ============================================================================

module tse_packet_processor (
    input  wire        clk,
    input  wire        rst_n,

    // --- TSE IP 流接口 ---
    input  wire [7:0]  tse_rx_data,
    input  wire        tse_rx_dv,
    input  wire        tse_rx_sop,
    input  wire        tse_rx_eop,
    output reg  [7:0]  tse_tx_data,
    output reg         tse_tx_wren,
    output reg         tse_tx_sop,
    output reg         tse_tx_eop,
    input  wire        tse_tx_ready,

    // --- 双口 RAM 接口 ---
    output wire [10:0] rx_ram_w_addr,
    output wire        rx_ram_w_en,
    output wire [7:0]  rx_ram_w_data,
    output wire [10:0] rx_ram_r_addr,
    input  wire [7:0]  rx_ram_r_data,
    output wire [10:0] tx_ram_w_addr,
    output wire [7:0]  tx_ram_w_data,
    output wire        tx_ram_w_en,
    output reg  [10:0] tx_ram_r_addr,
    input  wire [7:0]  tx_ram_r_data,

    output wire [3:0]  debug_state
);

    // --- 身份参数 ---
    localparam MY_MAC = 48'h02_00_00_00_00_01;
    localparam MY_IP  = {8'd192, 8'd168, 8'd1, 8'd123};

    // 状态机状态
    localparam S_IDLE   = 0, S_RX     = 1, S_DECIDE = 2, 
               S_WORK   = 3, S_TX_PRE = 4, S_TX_STR = 5;

    reg [3:0]  state;
    reg [10:0] pkt_len_reg, cnt_tx;
    reg [15:0] eth_type;
    reg        is_arp, is_udp;

    // --- 实时嗅探寄存器 ---
    reg [47:0] rem_mac_sniff;
    reg [31:0] rem_ip_sniff;

    // 子模块连线
    wire [10:0] arp_w_addr, udp_w_addr, udp_r_addr;
    wire [7:0]  arp_w_data, udp_w_data;
    wire        arp_w_en, udp_w_en, arp_done, udp_done;

    assign debug_state = state;

    // 1. 接收路径：确保 SOP 对应地址 0
    assign rx_ram_w_en   = (state == S_IDLE && tse_rx_sop) || (state == S_RX && tse_rx_dv);
    assign rx_ram_w_addr = (state == S_IDLE && tse_rx_sop) ? 0 : pkt_len_reg;
    assign rx_ram_w_data = tse_rx_data;

    // 2. 主逻辑状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rem_mac_sniff <= 0;
            rem_ip_sniff <= 0;
            eth_type <= 0;
            is_arp <= 0;
            is_udp <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    is_arp <= 0;
                    is_udp <= 0;
                    if (tse_rx_sop) begin 
                        state <= S_RX; 
                        pkt_len_reg <= 11'd1; // 下一拍地址从 1 开始
                        rem_mac_sniff <= 0;
                        rem_ip_sniff <= 0;
                    end
                end

                S_RX: if (tse_rx_dv) begin
                    pkt_len_reg <= pkt_len_reg + 1'b1;
                    
                    // --- 修正后的嗅探逻辑 (基于 1-based 偏移计数) ---
                    // 当 state 从 IDLE 跳到 RX，第一拍进来的其实是包的第 2 字节，此时 pkt_len_reg=1
                    // 以太网类型在第 13, 14 字节 -> 对应计数器 12, 13
                    if (pkt_len_reg == 11'd12) eth_type[15:8] <= tse_rx_data;
                    if (pkt_len_reg == 11'd13) eth_type[ 7:0] <= tse_rx_data;
                    
                    // 对方 MAC 在 ARP 帧偏移 23-28 字节 -> 对应计数器 22-27
                    if (pkt_len_reg >= 11'd22 && pkt_len_reg <= 11'd27) 
                        rem_mac_sniff <= {rem_mac_sniff[39:0], tse_rx_data};
                    // 对方 IP 在 ARP 帧偏移 29-32 字节 -> 对应计数器 28-31
                    if (pkt_len_reg >= 11'd28 && pkt_len_reg <= 11'd31) 
                        rem_ip_sniff <= {rem_ip_sniff[23:0], tse_rx_data};

                    if (tse_rx_eop) state <= S_DECIDE;
                end

                S_DECIDE: begin
                    // 只有明确匹配的协议才进入 WORK 状态
                    if (eth_type == 16'h0806 || eth_type == 16'h0800) begin
                        is_arp <= (eth_type == 16'h0806);
                        is_udp <= (eth_type == 16'h0800);
                        state  <= S_WORK;
                    end else begin
                        state  <= S_IDLE; // 未知协议直接丢弃
                    end
                end

                S_WORK: begin
                    if (arp_done || udp_done) begin
                        state <= S_TX_PRE;
                        if (is_arp) pkt_len_reg <= 11'd42; // ARP 回复包固定 42 字节
                    end
                end

                S_TX_PRE: begin
                    if (tse_tx_ready) begin
                        state <= S_TX_STR;
                        cnt_tx <= 0;
                        tx_ram_r_addr <= 0; // 预读首字节
                    end
                end

                S_TX_STR: if (tse_tx_ready) begin
                    if (cnt_tx < pkt_len_reg - 1) begin
                        cnt_tx <= cnt_tx + 1'b1;
                        tx_ram_r_addr <= tx_ram_r_addr + 1'b1;
                    end else begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // 子模块例化保持不变，但确保连线正确
    arp_processor u_arp (
        .clk(clk), .rst_n(rst_n), .local_mac(MY_MAC), .local_ip(MY_IP),
        .rem_mac_in(rem_mac_sniff), .rem_ip_in(rem_ip_sniff),
        .work_en(state == S_WORK && is_arp),
        .tx_ram_w_addr(arp_w_addr), .tx_ram_w_data(arp_w_data), .tx_ram_w_en(arp_w_en), .done(arp_done)
    );

    // ... UDP 处理器及仲裁逻辑保持不变 ...
    udp_processor u_udp (
        .clk(clk), .rst_n(rst_n),
        .work_en(state == S_WORK && is_udp), .pkt_len_in(pkt_len_reg),
        .rx_ram_r_addr(udp_r_addr), .rx_ram_r_data(rx_ram_r_data),
        .tx_ram_w_addr(udp_w_addr), .tx_ram_w_data(udp_w_data), .tx_ram_w_en(udp_w_en), .done(udp_done)
    );

    // 4. 资源调度仲裁
    assign rx_ram_r_addr = udp_r_addr; // ARP 模块现在已不需要回读 rx_ram
    assign tx_ram_w_addr = is_arp ? arp_w_addr : udp_w_addr;
    assign tx_ram_w_data = is_arp ? arp_w_data : udp_w_data;
    assign tx_ram_w_en   = is_arp ? arp_w_en   : udp_w_en;

    // 5. 最终输出驱动
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tse_tx_wren <= 0;
            tse_tx_sop  <= 0;
            tse_tx_eop  <= 0;
        end else if (state == S_TX_STR && tse_tx_ready) begin
            tse_tx_wren <= 1'b1;
            tse_tx_sop  <= (cnt_tx == 0);
            tse_tx_eop  <= (cnt_tx == pkt_len_reg - 1);
        end else begin
            tse_tx_wren <= 0;
            tse_tx_sop  <= 0;
            tse_tx_eop  <= 0;
        end
    end

    // 数据同步：由于 tx_ram_r_addr 在 PRE 阶段已设为 0，
    // 进入 STR 状态的第一拍，tx_ram_r_data 刚好是 Byte 0。
    always @(*) begin
        tse_tx_data = tx_ram_r_data;
    end
endmodule


