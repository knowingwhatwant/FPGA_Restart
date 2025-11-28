module udp_echo_top (
    input           clk,
    input           rst_n,

    // MII Interface
    input           enet0_rx_clk,
    input   [3:0]   enet0_rx_data,
    input           enet0_rx_dv,
    input           enet0_rx_er,
    input           enet0_tx_clk,
    output  [3:0]   enet0_tx_data,
    output          enet0_tx_en,
    output          enet0_tx_er,

    // MDIO Interface
    output          enet0_mdc,
    inout           enet0_mdio,
    output          enet0_rst_n,

    // 调试接口
    output wire       debug_rx_sop,
    output wire       debug_rx_dv,
    output wire [7:0] debug_rx_data,
    output wire       debug_rx_eop, // <--- 修正为真正的 RX EOP
    output wire       debug_phy_ready
);

    // ============================================================
    // 1. 信号定义 (精简掉不再需要的信号，保留必要的)
    // ============================================================
    wire mdio_mdc_w, mdio_mdio_out_w, mdio_mdio_in_w, mdio_mdio_oen_w, w_phy_rst_n; 
    wire [7:0]  av_addr;
    wire        av_read, av_write;
    wire [31:0] av_writedata, av_readdata;
    wire        av_waitrequest;

    // TSE RX/TX 接口信号
    wire [7:0] tse_rx_data;
    wire       tse_rx_dv, tse_rx_sop, tse_rx_eop;
    wire [7:0] tse_tx_data;   // 现在是 wire，由 loopback 模块驱动
    wire       tse_tx_wren, tse_tx_sop, tse_tx_eop; // 现在是 wire
    wire       tse_tx_ready;

    // RX RAM 读写控制信号 (由 loopback 模块驱动)
    wire [10:0] rx_ram_w_addr;
    wire        rx_ram_w_en;
    wire [10:0] rx_ram_r_addr;
    wire [7:0]  rx_ram_r_data;

    wire [10:0] tx_ram_w_addr;
    wire [7:0]  tx_ram_w_data;
    wire        tx_ram_w_en;
    wire [10:0] tx_ram_r_addr;
    wire [7:0]  tx_ram_r_data;


    // 定义连接线
    wire        pulse_trig_sig;
    wire [15:0] pulse_count_sig; // [新增] 传输数量的线
    wire        pulse_out_pin;   // 最终输出脚



    // ============================================================
    // 2. 连线与模块
    // ============================================================
    assign enet0_rst_n    = w_phy_rst_n;
    assign enet0_mdc      = mdio_mdc_w;
    assign enet0_mdio     = !mdio_mdio_oen_w ? mdio_mdio_out_w : 1'bz; 
    assign mdio_mdio_in_w = enet0_mdio;

    assign debug_rx_sop    = tse_tx_sop;         // 新: TX 帧开始
    assign debug_rx_dv     = tse_tx_wren;        // 新: TX 数据有效
    assign debug_rx_data   = tse_tx_data;        // 新: TX 数据
    assign debug_rx_eop    = tse_tx_eop;         // 新: TX 帧结束
    assign debug_phy_ready = w_phy_rst_n;        // 保持不变

    mdio_config_ctrl u_mdio_config (
        .clk(clk), .rst_n(rst_n),
        .o_av_addr(av_addr), .o_av_read(av_read), .o_av_write(av_write),
        .o_av_writedata(av_writedata), .i_av_readdata(av_readdata),
        .i_av_waitrequest(av_waitrequest), .o_phy_rst_n(w_phy_rst_n)
    );

    IPcore ipcore_inst (
        .clk(clk), .reset(~rst_n),
        .ff_rx_clk(clk), .ff_tx_clk(clk),
        .tx_clk(enet0_tx_clk), .rx_clk(enet0_rx_clk),
        .m_rx_d(enet0_rx_data), .m_rx_en(enet0_rx_dv), .m_rx_err(enet0_rx_er),
        .m_tx_d(enet0_tx_data), .m_tx_en(enet0_tx_en), .m_tx_err(enet0_tx_er),
        .mdc(mdio_mdc_w), .mdio_in(mdio_mdio_in_w), .mdio_out(mdio_mdio_out_w), .mdio_oen(mdio_mdio_oen_w),
        .reg_addr(av_addr), .reg_rd(av_read), .reg_wr(av_write),
        .reg_data_in(av_writedata), .reg_data_out(av_readdata), .reg_busy(av_waitrequest),
        .ff_tx_data(tse_tx_data), .ff_tx_wren(tse_tx_wren),
        .ff_tx_sop(tse_tx_sop), .ff_tx_eop(tse_tx_eop), .ff_tx_err(1'b0), .ff_tx_rdy(tse_tx_ready),
        .ff_rx_rdy(1'b1), .ff_rx_data(tse_rx_data), .ff_rx_dval(tse_rx_dv),
        .ff_rx_sop(tse_rx_sop), .ff_rx_eop(tse_rx_eop), .rx_err(),
        .m_rx_crs(0), .m_rx_col(0), .gm_rx_d(0), .gm_rx_dv(0), .gm_rx_err(0),
        .set_10(0), .set_1000(0), .xon_gen(0), .xoff_gen(0), .ff_tx_crc_fwd(0)
    );

    // 关闭 Output Registers 的 RAM
    ram_2port_2048 rx_ram_inst (
        .clock(clk),
        .address_a(rx_ram_w_addr), .data_a(tse_rx_data), .wren_a(rx_ram_w_en), .rden_a(1'b0), .q_a(),
        .address_b(rx_ram_r_addr), .data_b(8'd0),        .wren_b(1'b0),        .rden_b(1'b1), .q_b(rx_ram_r_data)
    );

    // ... 实例化 TX RAM (A写, B读) ...
    ram_2port_2048 tx_ram_inst (
        .clock(clk),
        .address_a(tx_ram_w_addr), .data_a(tx_ram_w_data), .wren_a(tx_ram_w_en), .rden_a(1'b0), .q_a(),
        .address_b(tx_ram_r_addr), .data_b(8'd0),          .wren_b(1'b0),        .rden_b(1'b1), .q_b(tx_ram_r_data)
    );

// 实例化 Pulse Generator
    pulse_generator u_pulse_gen (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_trig   (pulse_trig_sig),
        .pulse_num_in (pulse_count_sig), // [新增] 连接数量信号
        .pulse_out    (pulse_out_pin),
        .busy         () 
    );


  // ... 实例化 tse_packet_processor ...
    tse_packet_processor u_processor (
        .clk(clk), .rst_n(rst_n),
        // RX
        .tse_rx_data(tse_rx_data), .tse_rx_dv(tse_rx_dv), .tse_rx_sop(tse_rx_sop), .tse_rx_eop(tse_rx_eop),
        // RX RAM Ctrl
        .rx_ram_w_addr(rx_ram_w_addr), .rx_ram_w_en(rx_ram_w_en),
        .rx_ram_r_data(rx_ram_r_data), .rx_ram_r_addr(rx_ram_r_addr),
        // TX RAM Ctrl (新增连接)
        .tx_ram_w_addr(tx_ram_w_addr), .tx_ram_w_data(tx_ram_w_data), .tx_ram_w_en(tx_ram_w_en),
        .tx_ram_r_data(tx_ram_r_data), .tx_ram_r_addr(tx_ram_r_addr),
        // TX
        .tse_tx_data(tse_tx_data), .tse_tx_wren(tse_tx_wren),
        .tse_tx_sop(tse_tx_sop), .tse_tx_eop(tse_tx_eop), .tse_tx_ready(tse_tx_ready),
        .pulse_start_trig (pulse_trig_sig),
        .pulse_target_val (pulse_count_sig) // [新增] 输出数量信号
    );

endmodule