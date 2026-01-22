module udp_echo_top (
    input           clk,
    input           rst_n,

    // RGMII Interface (replaces MII)
    input           enet0_rx_clk,      // RGMII RX Clock from PHY
    input   [3:0]   enet0_rgmii_rx,    // RGMII RX Data
    input           enet0_rx_ctl,      // RGMII RX Control (RX_DV)

    output          enet0_tx_clk,      // RGMII TX Clock (driven by FPGA)
    output  [3:0]   enet0_rgmii_tx,    // RGMII TX Data
    output          enet0_tx_ctl,      // RGMII TX Control (TX_EN)


    // MDIO Interface
    output          enet0_mdc,
    inout           enet0_mdio,
    output          enet0_rst_n,

    // ========================================================
    // 调试端口 (用于引出到顶层观察或 SignalTap)
    // ========================================================
    
    // 1. MDIO 配置状态调试
    output          dbg_cfg_done,     // 配置是否完成 (Done=1)
    output [3:0]    dbg_cfg_state,    // 配置状态机当前位置
    output [3:0]    dbg_state,
    
    // 2. 内部接收总线 (IP -> 用户逻辑)
    // 这一组信号最关键：确认包是否正确穿过了 IP 核
    output [7:0]    dbg_rx_data,      // 内部解出的 8-bit 数据流
    output          dbg_rx_dv,        // 数据有效信号
    output          dbg_rx_sop,       // 帧起始
    output          dbg_rx_eop,       // 帧结束
    
    // 3. 内部发送总线 (用户逻辑 -> IP)
    // 这一组信号确认你的 Echo 逻辑是否正在尝试回包
    output [7:0]    dbg_tx_data,      // 你发给 IP 的数据
    output          dbg_tx_wren,      // 发送使能
    output          dbg_tx_sop,       // 发送帧起始
    output          dbg_tx_eop,       // 发送帧结束


    // 脉冲输出
    output  [2:0]    pulse_out,

      
    // 5. 其他关键状态
    // output [15:0]   dbg_phy_id1,      // 读到的 ID1 (0x001C)


    // // 1. RX RAM 监控 (PHY -> FPGA 存入过程)
    // output          dbg_rx_ram_w_en,   // 写使能：为高代表正在往内存存数据
    // output [10:0]   dbg_rx_ram_w_addr, // 写地址：看是否随数据包递增
    // output [7:0]    dbg_rx_ram_w_data, // 写数据：应对应 tse_rx_data
    // output [10:0]   dbg_rx_ram_r_addr, // 读地址：解析模块读取时的位置
    // output [7:0]    dbg_rx_ram_r_data, // 读数据：解析模块拿到的数据
    
    // // 2. TX RAM 监控 (FPGA -> PHY 准备过程)
    // output          dbg_tx_ram_w_en,   // 写使能：处理完后往发送内存存
    // output [10:0]   dbg_tx_ram_w_addr, // 写地址
    // output [7:0]    dbg_tx_ram_w_data, // 写数据：修改过报头后的数据
    // output [10:0]   dbg_tx_ram_r_addr, // 读地址：TSE IP 发送读取时的位置
    // output [7:0]    dbg_tx_ram_r_data, // 读数据：送往 TSE IP 的数据
    
   
    output          dbg_tx_ready       // 发送 FIFO 准备好
);

    // ============================================================
    // 1. 信号定义 (精简掉不再需要的信号，保留必要的)
    // ============================================================
    wire mdio_mdc_w, mdio_mdio_out_w, mdio_mdio_in_w, mdio_mdio_oen_w, w_phy_rst_n; 
    wire [7:0]  av_addr;
    wire        av_read, av_write;
    wire [31:0] av_writedata, av_readdata;
    wire        av_waitrequest/* synthesis keep */;

    // TSE RX/TX 接口信号
    wire [7:0] tse_rx_data;
    wire       tse_rx_dv, tse_rx_sop, tse_rx_eop;
    wire [7:0] tse_tx_data;
    wire       tse_tx_wren, tse_tx_sop, tse_tx_eop; // 现在是 wire
    wire       tse_tx_ready;

    wire pulse_valid/* synthesis keep */;
    wire [15:0] pulse_num[2:0]/* synthesis keep */;
    wire [7:0] cmd_type ;

    wire busy_x, busy_y, busy_z;
    assign pulse_busy = busy_x | busy_y | busy_z;
    // =================================================================
// 1. 时钟生成 (关键点)
// =================================================================
wire clk_tx_logic;     // 喂给 IP 核内部物理侧的时钟
wire clk_tx_out_90deg; // 喂给外部 PHY 引脚的时钟 (带相移以保证对齐)
wire pll_locked;

    // 使用 ALTPLL IP 核：输入 50M
    // c0: 25MHz (百兆模式) 或 125MHz (千兆模式) - 0度
    // c1: 25MHz (百兆模式) 或 125MHz (千兆模式) - 90度相移 (非常重要)
    PLL u_pll (
        .inclk0 (clk),
        .c0     (clk_tx_logic),
        .c1     (clk_tx_out_90deg),
        .locked (pll_locked)
    );
    // 物理引脚驱动：将带相移的时钟输出给 PHY
assign enet0_tx_clk = clk_tx_out_90deg;


    wire [15:0] w_phy_id1, w_phy_id2;

    // RX RAM 读写控制信号 
    wire [10:0] rx_ram_w_addr  /* synthesis keep */;
    wire        rx_ram_w_en  /* synthesis keep */;
    wire [10:0] rx_ram_r_addr  /* synthesis keep */;
    wire [7:0]  rx_ram_r_data /* synthesis keep */;

    wire [10:0] tx_ram_w_addr;
    wire [7:0]  tx_ram_w_data;
    wire        tx_ram_w_en;
    wire [10:0] tx_ram_r_addr;
    wire [7:0]  tx_ram_r_data;


    // 定义连接线
    wire        pulse_trig_sig;
    wire [15:0] pulse_count_sig; // [新增] 传输数量的线
    wire        pulse_out_pin;   // 最终输出脚


    assign dbg_cfg_done    = debug_cfg_done; // 映射自 mdio_config 模块
//    assign dbg_cfg_state   = debug_cfg_state;
    // assign dbg_phy_id1     = w_phy_id1;
    
    // 接收流调试 (IP -> User Logic)
    assign dbg_rx_data     = tse_rx_data;
    assign dbg_rx_dv       = tse_rx_dv;
    assign dbg_rx_sop      = tse_rx_sop;
    assign dbg_rx_eop      = tse_rx_eop;
    
    // 发送流调试 (User Logic -> IP)
    assign dbg_tx_data     = tse_tx_data;
    assign dbg_tx_wren     = tse_tx_wren;
    assign dbg_tx_sop      = tse_tx_sop;
    assign dbg_tx_eop      = tse_tx_eop;
    assign dbg_tx_ready    = tse_tx_ready;

    // // --- 调试信号赋值 ---
    // assign dbg_rx_ram_w_en   = rx_ram_w_en;
    // assign dbg_rx_ram_w_addr = rx_ram_w_addr;
    // assign dbg_rx_ram_w_data = tse_rx_data; // 直接看输入
    // assign dbg_rx_ram_r_addr = rx_ram_r_addr;
    // assign dbg_rx_ram_r_data = rx_ram_r_data;

    // assign dbg_tx_ram_w_en   = tx_ram_w_en;
    // assign dbg_tx_ram_w_addr = tx_ram_w_addr;
    // assign dbg_tx_ram_w_data = tx_ram_w_data;
    // assign dbg_tx_ram_r_addr = tx_ram_r_addr;
    // assign dbg_tx_ram_r_data = tx_ram_r_data;

    assign dbg_rx_sop        = tse_rx_sop;
    assign dbg_rx_eop        = tse_rx_eop;
    assign dbg_tx_ready      = tse_tx_ready;


    // ============================================================
    // 2. 连线与模块
    // ============================================================
    assign enet0_rst_n    = w_phy_rst_n;
    assign enet0_mdc      = mdio_mdc_w;
    assign enet0_mdio     = !mdio_mdio_oen_w ? mdio_mdio_out_w : 1'bz; 
    assign mdio_mdio_in_w = enet0_mdio;


    mdio_config_ctrl_rtl8211f u_mdio_config (
        .clk(clk), .rst_n(rst_n),
        .o_av_addr(av_addr), .o_av_read(av_read), .o_av_write(av_write),
        .o_av_writedata(av_writedata), .i_av_readdata(av_readdata),
        .i_av_waitrequest(av_waitrequest), .o_phy_rst_n(w_phy_rst_n),
        .r_phy_id1(w_phy_id1), .r_phy_id2(w_phy_id2),
        .o_cfg_done(debug_cfg_done),
    );

    TSE_RGMII ipcore_inst (
        .clk(clk), .reset(~rst_n | ~pll_locked),
        .ff_rx_clk(clk), .ff_tx_clk(clk),
        .tx_clk(clk_tx_logic), 
        .rx_clk(enet0_rx_clk),
        // RGMII data & control
        .rgmii_in(enet0_rgmii_rx),     // ← 替换原来的 m_rx_d[3:0]
        .rgmii_out(enet0_rgmii_tx),    // ← 替换原来的 m_tx_d[3:0]
        .rx_control(enet0_rx_ctl),     // ← 替换 enet0_rx_dv / enet0_rx_er
        .tx_control(enet0_tx_ctl),     // ← 替换 enet0_tx_en / enet0_tx_er
        // MDIO
        .mdc(mdio_mdc_w), .mdio_in(mdio_mdio_in_w), .mdio_out(mdio_mdio_out_w), .mdio_oen(mdio_mdio_oen_w),
        // Register interface
        .reg_addr(av_addr), .reg_rd(av_read), .reg_wr(av_write),
        .reg_data_in(av_writedata), .reg_data_out(av_readdata), .reg_busy(av_waitrequest),
        // FIFO interface (keep unchanged)
        .ff_tx_data(tse_tx_data), .ff_tx_wren(tse_tx_wren),
        .ff_tx_sop(tse_tx_sop), .ff_tx_eop(tse_tx_eop), .ff_tx_err(1'b0), .ff_tx_rdy(tse_tx_ready),
        .ff_rx_rdy(1'b1), .ff_rx_data(tse_rx_data), .ff_rx_dval(tse_rx_dv),
        .ff_rx_sop(tse_rx_sop), .ff_rx_eop(tse_rx_eop), .rx_err(),
        .set_10(0), .set_1000(0),.ff_tx_crc_fwd(0)
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
        .out_cmd_type(cmd_type),  
        .out_x_val(pulse_num[2]),     
        .out_y_val(pulse_num[1]),     
        .out_z_val(pulse_num[0]),     
        .out_data_valid(pulse_valid),
        // // --- Debug ---
        .debug_state(dbg_state)
    );

    pulse_generator u_pulse_gen_x (
        .clk(clk), .rst_n(rst_n),
        .start_trig(pulse_valid),
        .pulse_num_in(pulse_num[2]),
        .pulse_out(pulse_out[2]),
        .busy(busy_x)
    );

    pulse_generator u_pulse_gen_y (
        .clk(clk), .rst_n(rst_n),
        .start_trig(pulse_valid),
        .pulse_num_in(pulse_num[1]),
        .pulse_out(pulse_out[1]),
        .busy(busy_y)
    );
    pulse_generator u_pulse_gen_z (
        .clk(clk), .rst_n(rst_n),
        .start_trig(pulse_valid),
        .pulse_num_in(pulse_num[0]),
        .pulse_out(pulse_out[0]),
        .busy(busy_z)
    );



endmodule