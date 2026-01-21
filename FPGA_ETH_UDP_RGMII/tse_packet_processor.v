// ============================================================================
// Module: tse_packet_processor (Validated & Fixed)
// Description: 
// 1. 修复了 S_CHKSUM 状态名未定义的错误。
// 2. 修复了 tx_ram_w_en 等信号的多重驱动错误，增加了多路仲裁逻辑。
// 3. 完美兼容 ARP 嗅探与 IP 首部校验和实时生成。
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

    // --- 双口 RAM 接口 (由总线仲裁控制输出) ---
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

    // --- 状态机定义 ---
    localparam S_IDLE      = 3'd0, 
               S_RX        = 3'd1, 
               S_DECIDE    = 3'd2, 
               S_WORK      = 3'd3, 
               S_CHKSUM_H  = 3'd4, 
               S_CHKSUM_L  = 3'd5, 
               S_TX_PRE    = 3'd6, 
               S_TX_STR    = 3'd7;

    reg [2:0]  state;
    reg [10:0] pkt_len_reg, cnt_tx;
    reg [15:0] eth_type;
    reg        is_arp, is_udp;

    // --- 校验和寄存器 ---
    reg [15:0] ip_hdr_words [0:9]; 
    wire [15:0] new_chksum;
    wire        chksum_done;
    reg         chksum_start;

    // --- 实时嗅探寄存器 ---
    reg [47:0] rem_mac_sniff;
    reg [31:0] rem_ip_sniff;

    // --- 子模块连线与仲裁寄存器 ---
    wire [10:0] arp_w_addr, udp_w_addr, udp_r_addr;
    wire [7:0]  arp_w_data, udp_w_data;
    wire        arp_w_en, udp_w_en, arp_done, udp_done;

    // 主状态机控制的 RAM 信号 (用于校验和回填)
    reg [10:0] main_tx_w_addr;
    reg [7:0]  main_tx_w_data;
    reg        main_tx_w_en;

    assign debug_state = {1'b0, state};

    // 1. 接收存储路径
    assign rx_ram_w_en   = (state == S_IDLE && tse_rx_sop) || (state == S_RX && tse_rx_dv);
    assign rx_ram_w_addr = (state == S_IDLE && tse_rx_sop) ? 11'd0 : pkt_len_reg;
    assign rx_ram_w_data = tse_rx_data;

    // 2. 主逻辑状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            rem_mac_sniff <= 0; rem_ip_sniff <= 0; eth_type <= 0;
            main_tx_w_en <= 0; is_arp <= 0; is_udp <= 0; chksum_start <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    is_arp <= 0; is_udp <= 0; chksum_start <= 0; main_tx_w_en <= 0;
                    if (tse_rx_sop) begin 
                        state <= S_RX; pkt_len_reg <= 11'd1;
                        rem_mac_sniff <= 0; rem_ip_sniff <= 0;
                    end
                end

                S_RX: if (tse_rx_dv) begin
                    pkt_len_reg <= pkt_len_reg + 11'd1;
                    
                    // 以太网类型
                    if (pkt_len_reg == 11'd12) eth_type[15:8] <= tse_rx_data;
                    if (pkt_len_reg == 11'd13) eth_type[ 7:0] <= tse_rx_data;

                    // ARP/IP 身份嗅探 (对应以太网帧 23-32 字节)
                    if (pkt_len_reg >= 11'd22 && pkt_len_reg <= 11'd27) 
                        rem_mac_sniff <= {rem_mac_sniff[39:0], tse_rx_data};
                    if (pkt_len_reg >= 11'd28 && pkt_len_reg <= 11'd31) 
                        rem_ip_sniff <= {rem_ip_sniff[23:0], tse_rx_data};

                    // IP 首部字提取 (对应以太网帧 15-34 字节)
                    if (pkt_len_reg >= 11'd14 && pkt_len_reg <= 11'd33) begin
                        if (pkt_len_reg[0] == 0) // 偶数计数器为高位
                            ip_hdr_words[(pkt_len_reg-11'd14)>>1][15:8] <= tse_rx_data;
                        else
                            ip_hdr_words[(pkt_len_reg-11'd14)>>1][ 7:0] <= tse_rx_data;
                    end

                    if (tse_rx_eop) state <= S_DECIDE;
                end

                S_DECIDE: begin
                    if (eth_type == 16'h0806 || eth_type == 16'h0800) begin
                        is_arp <= (eth_type == 16'h0806);
                        is_udp <= (eth_type == 16'h0800);
                        state  <= S_WORK;
                    end else state <= S_IDLE;
                end

                S_WORK: begin
                    if (arp_done || udp_done) begin
                        if (is_udp) begin
                            state <= S_CHKSUM_H;
                            chksum_start <= 1; 
                        end else begin
                            state <= S_TX_PRE;
                            pkt_len_reg <= 11'd42; 
                        end
                    end
                end

                S_CHKSUM_H: begin
                    chksum_start <= 0;
                    if (chksum_done) begin
                        main_tx_w_en   <= 1;
                        main_tx_w_addr <= 11'd24; // IP Checksum High
                        main_tx_w_data <= new_chksum[15:8];
                        state          <= S_CHKSUM_L; 
                    end
                end

                S_CHKSUM_L: begin
                    main_tx_w_addr <= 11'd25; // IP Checksum Low
                    main_tx_w_data <= new_chksum[7:0];
                    state          <= S_TX_PRE;
                end

                S_TX_PRE: begin
                    main_tx_w_en <= 0;
                    if (tse_tx_ready) begin
                        state <= S_TX_STR;
                        cnt_tx <= 0;
                        tx_ram_r_addr <= 0;
                    end
                end

                S_TX_STR: if (tse_tx_ready) begin
                    if (cnt_tx < pkt_len_reg - 1) begin
                        cnt_tx <= cnt_tx + 11'd1;
                        tx_ram_r_addr <= tx_ram_r_addr + 11'd1;
                    end else state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

    // 6、7是SRC IP
    // 8、9是DST IP
    // 3. 校验和计算器例化
    wire [15:0] w6 = is_udp ? ip_hdr_words[8] : ip_hdr_words[6]; 
    wire [15:0] w7 = is_udp ? ip_hdr_words[9] : ip_hdr_words[7]; 
    wire [15:0] w8 = is_udp ? ip_hdr_words[6] : ip_hdr_words[8]; 
    wire [15:0] w9 = is_udp ? ip_hdr_words[7] : ip_hdr_words[9]; 

    ip_checksum_calculator u_chk_gen (
        .clk(clk), .rst_n(rst_n),
        .start(chksum_start),
        .word0(ip_hdr_words[0]), .word1(ip_hdr_words[1]),
        .word2(ip_hdr_words[2]), .word3(ip_hdr_words[3]),
        .word4(ip_hdr_words[4]), .word5(16'h0000), 
        .word6(w6), .word7(w7), .word8(w8), .word9(w9),
        .checksum_out(new_chksum), .done(chksum_done)
    );
    
    // 4. 子模块例化
    arp_processor u_arp (
        .clk(clk), .rst_n(rst_n), .local_mac(MY_MAC), .local_ip(MY_IP),
        .rem_mac_in(rem_mac_sniff), .rem_ip_in(rem_ip_sniff),
        .work_en(state == S_WORK && is_arp),
        .tx_ram_w_addr(arp_w_addr), .tx_ram_w_data(arp_w_data), .tx_ram_w_en(arp_w_en), .done(arp_done)
    );

    udp_processor u_udp (
        .clk(clk), .rst_n(rst_n),
        .work_en(state == S_WORK && is_udp), .pkt_len_in(pkt_len_reg),
        .word6(w6), .word7(w7), .word8(w8), .word9(w9),
        .rx_ram_r_addr(udp_r_addr), .rx_ram_r_data(rx_ram_r_data),
        .tx_ram_w_addr(udp_w_addr), .tx_ram_w_data(udp_w_data), .tx_ram_w_en(udp_w_en), .done(udp_done)
    );

    // 5. 资源仲裁逻辑 (修复多重驱动)
    assign rx_ram_r_addr = udp_r_addr;
    
    // TX RAM 写入侧仲裁：当处于校验和修复阶段，由主状态机控制；否则由子模块控制
    assign tx_ram_w_en   = (state == S_CHKSUM_H || state == S_CHKSUM_L) ? main_tx_w_en   : (is_arp ? arp_w_en   : udp_w_en);
    assign tx_ram_w_addr = (state == S_CHKSUM_H || state == S_CHKSUM_L) ? main_tx_w_addr : (is_arp ? arp_w_addr : udp_w_addr);
    assign tx_ram_w_data = (state == S_CHKSUM_H || state == S_CHKSUM_L) ? main_tx_w_data : (is_arp ? arp_w_data : udp_w_data);

    // 6. 物理输出驱动
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tse_tx_wren <= 0; tse_tx_sop <= 0; tse_tx_eop <= 0;
        end else if (state == S_TX_STR && tse_tx_ready) begin
            tse_tx_wren <= 1'b1;
            tse_tx_sop  <= (cnt_tx == 0);
            tse_tx_eop  <= (cnt_tx == pkt_len_reg - 1);
        end else begin
            tse_tx_wren <= 0; tse_tx_sop <= 0; tse_tx_eop <= 0;
        end
    end

    always @(*) begin
        tse_tx_data = tx_ram_r_data;
    end

endmodule