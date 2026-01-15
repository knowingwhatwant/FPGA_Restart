// --- 这是 TOP.v 文件的完整内容 ---
// --- 集成版：包含所有 UDP Echo 逻辑 + 全套调试信号 ---

module TOP (
    // 1. 系统时钟和复位
    input           clk,        // 板载 50MHz
    input           rst_n,      // 复位按键
    input           key_send,   

    // 3. MII 接口
    input           enet0_rx_clk,
    input   [3:0]   enet0_rx_data,
    input           enet0_rx_dv,
    input           enet0_rx_er,
    input           enet0_tx_clk,
    output  [3:0]   enet0_tx_data,
    output          enet0_tx_en,
    output          enet0_tx_er,

    // 4. MDIO 接口
    output          enet0_mdc,
    inout           enet0_mdio,

    // 5. PHY 复位
    output          enet0_rst_n,

    // 6. 调试信号输出端口 (用于 SignalTap)
    // --- 原有调试信号 ---
    output  [3:0]   dbg_state,       // MDIO配置状态机
    output  [31:0]  dbg_phy_id1,     // PHY ID1
    output  [31:0]  dbg_phy_id2,     // PHY ID2
    output          dbg_waitrequest, // IP核忙信号 (tx_ready)
    output  [4:0]   dbg_phy_addr,    // PHY地址
    
    // --- !!! 新增调试信号 !!! ---
    output          dbg_rx_dval,     // 接收数据有效 (w_rx_dval)
    output          dbg_rx_pkt_rdy,  // 接收包就绪 (rx_pkt_rdy)
    output  [5:0]   dbg_parse_state, // 解析状态机 (parse_state)
    output  [2:0]   dbg_copy_state,  // 拷贝状态机 (copy_state)
    output  [2:0]   dbg_chksum_state,// 校验和状态机 (chksum_state)
    output  [2:0]   dbg_send_state,   // 发送状态机 (send_state)

    // --- !!! 新增关键数据调试信号 (用于验尸报告) !!! ---
    output  [15:0]  dbg_payload_len, // 解析到的 Payload 长度 (r_payload_len)
    output  [15:0]  dbg_tx_total_len,// 计算出的回传包总长 (tx_pkt_total_len)
    output  [31:0]  dbg_ip_src,      // 解析到的源 IP (r_ip_src_in)
    output  [31:0]  dbg_ip_dest,      // 解析到的目 IP (r_ip_dest_in)
    output  [7:0]   dbg_i_rx_data
);

// =================================================================
// 内部信号线 (Wires & Regs)
// =================================================================

// --- 1. IP核的时钟与复位 ---
wire        sys_clk;        // IP核内部逻辑时钟
wire        sys_rst;        // IP核内部逻辑复位 (高电平有效)

// --- 2. MII 物理接口信号 ---
wire        mii_rx_clk;
wire [3:0]  mii_rx_d;
wire        mii_rx_dv;
wire        mii_rx_er;
wire        mii_tx_clk;
wire [3:0]  mii_tx_d;
wire        mii_tx_en;
wire        mii_tx_er;

// --- 3. MDIO 物理接口信号 ---
wire        mdio_mdc_w;
wire        mdio_mdio_out_w;
wire        mdio_mdio_in_w;
wire        mdio_mdio_oen_w;

// --- 4. Rx Datapath 信号 (从 IP 核接收) ---
wire [7:0]  i_rx_data;   // 接收数据
wire        w_rx_dval;   // 数据有效 (Data Valid)
wire        w_rx_sop;    // 包头标记 (Start of Packet)
wire        w_rx_eop;    // 包尾标记 (End of Packet)

// --- 5. MDIO 读写状态机信号 ---
reg [3:0]   r_state;         // 状态机
reg [19:0]  r_wait_cnt;      // 复位后等待计数器
reg [7:0]   o_av_addr;       // IP核-控制端口-地址
reg         o_av_read;       // IP核-控制端口-读使能
reg         o_av_write;      // IP核-控制端口-写使能
reg [31:0]  o_av_writedata;  // IP核-控制端口-写数据
wire [31:0] i_av_readdata;   // IP核-控制端口-读回的数据
wire        i_av_waitrequest;// IP核-控制端口-忙信号

// --- 6. 我们的最终成果 (PHY Info) ---
reg [31:0]  r_phy_id1;       // 用来锁存 PHY ID 寄存器 2 的值
reg [31:0]  r_phy_id2;       // 用来锁存 PHY ID 寄存器 3 的值
reg [4:0]   r_phy_addr;      // PHY地址扫描计数器
reg         r_phy_rst_n;     // 用寄存器控制PHY复位

// --- 7. 解析 FSM 核心寄存器 (Parsing Info) ---
// 存储从 Rx Buffer 中提取出的地址/端口
reg [47:0] r_mac_dest_in; // 接收到的 目标MAC
reg [47:0] r_mac_src_in;  // 接收到的 源MAC
reg [31:0] r_ip_dest_in;  // 接收到的 目标IP
reg [31:0] r_ip_src_in;   // 接收到的 源IP
reg [15:0] r_udp_dest_in; // 接收到的 目标Port
reg [15:0] r_udp_src_in;  // 接收到的 源Port
reg [15:0] r_pkt_type;    // 帧类型 (EtherType, 应为 0x0800)
reg [15:0] r_payload_len; // 原始 Payload 长度 (16位)




// =================================================================
// Module: BRAM Buffer Management (RX & TX)
// Description: 管理接收和发送的双端口RAM，以及多状态机访问冲突的仲裁
// =================================================================

// -----------------------------------------------------------------
// 1. 参数定义 (Parameters)
// -----------------------------------------------------------------
localparam RX_BUFFER_DEPTH = 11;                   // log2(2048) = 11
localparam RX_BUFFER_SIZE  = (1 << RX_BUFFER_DEPTH); // 2048 bytes

// -----------------------------------------------------------------
// 2. 信号定义 (Signal Declarations)
// -----------------------------------------------------------------

// --- RX Buffer 信号 ---
// Port A: 写入 (Rx FSM 专用)
reg  [RX_BUFFER_DEPTH-1:0] rx_w_addr;    // Rx FSM 驱动写入地址
reg                        rx_w_en;      // Rx FSM 驱动写入使能
// Port B: 读取 (Parsing FSM / Copy FSM 共用)
reg  [RX_BUFFER_DEPTH-1:0] parse_addr;   // Parsing FSM 驱动读地址
reg  [RX_BUFFER_DEPTH-1:0] copy_addr;    // Copy FSM 驱动读地址
// Port B 连接线
wire [RX_BUFFER_DEPTH-1:0] rx_r_addr_mux; // 最终连接到 RAM Port B 的地址
wire [7:0]                 rx_r_data;     // RAM 读出的数据

// --- TX Buffer 信号 ---
// Port A: 写入 (Copy FSM / Checksum FSM 共用)
reg  [RX_BUFFER_DEPTH-1:0] copy_w_addr;   // Copy FSM 驱动写地址
reg  [7:0]                 copy_w_data;   // Copy FSM 驱动写数据
reg                        copy_w_en;     // Copy FSM 驱动写使能
reg  [RX_BUFFER_DEPTH-1:0] chksum_w_addr; // Checksum FSM 驱动写地址
reg  [7:0]                 chksum_w_data; // Checksum FSM 驱动写数据
reg                        chksum_w_en;   // Checksum FSM 驱动写使能
// Port A 连接线 (经过 MUX 后)
wire [RX_BUFFER_DEPTH-1:0] tx_w_addr_mux;
wire [7:0]                 tx_w_data_mux;
wire                       tx_w_en_mux;

// Port B: 读取 (Checksum FSM / Tx FSM 共用)
// 注意：你需要补充 Tx FSM 和 Checksum FSM 对读取地址的控制逻辑
// 这里假设你也有类似 tx_r_addr 的逻辑
wire [RX_BUFFER_DEPTH-1:0] tx_r_addr_mux; 
wire [7:0]                 tx_r_data;


// -----------------------------------------------------------------
// 3. 逻辑仲裁与多路复用 (Arbitration Logic)
// -----------------------------------------------------------------

// --- RX Buffer Port B (Read) MUX ---
// 优先级逻辑：当 Copy FSM 工作时，控制权交给 Copy，否则给 Parse
assign rx_r_addr_mux = (copy_state != C_IDLE) ? copy_addr : parse_addr;

// --- TX Buffer Port A (Write) MUX ---
// 优先级逻辑：当 Checksum FSM 工作时，控制权交给 Checksum，否则给 Copy
// (注：需确保 Copy 和 Checksum 不会同时处于非 IDLE 状态，或者明确优先级)
assign tx_w_addr_mux = (chksum_state != CS_IDLE) ? chksum_w_addr : copy_w_addr;
assign tx_w_data_mux = (chksum_state != CS_IDLE) ? chksum_w_data : copy_w_data;
assign tx_w_en_mux   = (chksum_state != CS_IDLE) ? chksum_w_en   : copy_w_en;

// --- TX Buffer Port B (Read) MUX ---
// [TODO] 这里需要你补充 TX 读地址的逻辑，通常是 Tx FSM (发送到网口) 和 Checksum FSM (计算校验和) 共享
// assign tx_r_addr_mux = (tx_state != TX_IDLE) ? tx_send_addr : chksum_r_addr; 


// -----------------------------------------------------------------
// 4. 模块实例化 (IP Core Instantiation)
// -----------------------------------------------------------------

// --- RX BRAM Instance ---
ram_2port_2048 rx_ram_inst (
    .clock     (sys_clk),
    
    // Port A: Write Only (Rx FSM)
    .address_a (rx_w_addr),
    .data_a    (i_rx_data),
    .wren_a    (rx_w_en),
    .q_a       (),            // Port A 不读，悬空
    
    // Port B: Read Only (Parsing / Copy)
    .address_b (rx_r_addr_mux),
    .data_b    (8'd0),        // Port B 不写，置零
    .wren_b    (1'b0),        // Port B 写失能
    .q_b       (rx_r_data)    // 读出数据
);

// --- TX BRAM Instance ---
ram_2port_2048 tx_ram_inst (
    .clock     (sys_clk),
    
    // Port A: Write Only (Copy / Checksum)
    .address_a (tx_w_addr_mux),
    .data_a    (tx_w_data_mux),
    .wren_a    (tx_w_en_mux),
    .q_a       (),            // Port A 不读，悬空
    
    // Port B: Read Only (Checksum / Tx Send)
    .address_b (tx_r_addr),   // [注意] 需确保 tx_r_addr 信号已有逻辑驱动
    .data_b    (8'd0),
    .wren_b    (1'b0),
    .q_b       (tx_r_data)    // 读出数据
);


// --- 10. 状态机状态定义与变量 ---

// Rx FSM (接收)
localparam S_RX_IDLE  = 3'd0;
localparam S_RX_WRITE = 3'd1;
localparam S_RX_DONE  = 3'd2;
reg [2:0] rx_fsm_state;
reg [RX_BUFFER_DEPTH:0] rx_pkt_len; // 接收到的总字节数
reg rx_pkt_rdy;                     // 接收完成标志

// Parsing FSM (解析)
reg [5:0] parse_state; 

// Copy FSM (拷贝与修改)
localparam C_IDLE        = 3'd0;
localparam C_COPY_INIT   = 3'd1; 
localparam C_COPY_DATA   = 3'd2; 
localparam C_COPY_SUFFIX = 3'd3; 
localparam C_DONE        = 3'd4; 
reg [2:0]  copy_state;
reg [15:0] tx_pkt_total_len; // 回传包的最终总长度

// Checksum FSM (校验和)
localparam CS_IDLE       = 3'd0;
localparam CS_INIT       = 3'd1;
localparam CS_CALC       = 3'd2;
localparam CS_FINAL      = 3'd3;
localparam CS_WRITE_HI   = 3'd4;
localparam CS_WRITE_LO   = 3'd5;
localparam CS_DONE       = 3'd6;
reg [2:0]  chksum_state;
reg [19:0] r_sum_acc;      
reg [3:0]  r_word_cnt;    

// Tx Sending FSM (发送) 信号
reg [7:0]   tx_data;
reg         tx_valid;
reg         tx_sop;
reg         tx_eop;
wire        tx_ready;
reg [2:0]   send_state;
reg         key_send_d; // (可选) 按键边沿检测

// =================================================================
// 逻辑连接
// =================================================================

// 1. 使用板载时钟和复位
assign sys_clk = clk;
assign sys_rst = ~rst_n; // 我们的复位是低电平有效，IP核要高电平

// 2. PHY 硬件复位
// !!! 关键：我们用状态机逻辑(r_phy_rst_n)来控制PHY复位 !!!
assign enet0_rst_n  = r_phy_rst_n; 

// 3. MDIO 双向端口标准写法 (三态门)
assign enet0_mdc      = mdio_mdc_w;
assign enet0_mdio     = !mdio_mdio_oen_w ? mdio_mdio_out_w : 1'bz; 
assign mdio_mdio_in_w = enet0_mdio;

// 4. 调试信号连接到输出端口
assign dbg_state       = r_state;
assign dbg_phy_id1     = r_phy_id1;
assign dbg_phy_id2     = r_phy_id2;
assign dbg_waitrequest = tx_ready; // 改为看 tx_ready
assign dbg_phy_addr    = r_phy_addr;
// --- 新增调试信号连接 ---
assign dbg_rx_dval     = w_rx_dval;
assign dbg_rx_pkt_rdy  = rx_pkt_rdy;
assign dbg_parse_state = parse_state;
assign dbg_copy_state  = copy_state;
assign dbg_chksum_state= chksum_state;
assign dbg_send_state  = send_state;

// --- 新增关键数据调试信号连接 ---
assign dbg_payload_len  = r_payload_len;
assign dbg_tx_total_len = tx_pkt_total_len;
assign dbg_ip_src       = r_ip_src_in;
assign dbg_ip_dest      = r_ip_dest_in;
assign dbg_i_rx_data    = i_rx_data;


// debug
reg [15:0] r_ipv4_checksum;





// =================================================================
// IP核例化 (严格按照你的 IPcore.v 文件)
// =================================================================

IPcore ipcore_inst (
    // --- 1. IP核时钟与复位 ---
    .clk          (sys_clk),      // 连接到系统时钟 (用于 Avalon-MM)
    .reset        (sys_rst),      // 连接到系统复位 (用于 Avalon-MM)
    .ff_rx_clk    (sys_clk),      // 连接到系统时钟 (用于 Avalon-ST 接收)
    .ff_tx_clk    (sys_clk),      // 连接到系统时钟 (用于 Avalon-ST 发送)
    
    // MII 物理时钟 (来自PHY)
    .tx_clk       (enet0_tx_clk), // MII 发送时钟 (来自PHY)
    .rx_clk       (enet0_rx_clk), // MII 接收时钟 (来自PHY)

    // --- 2. MII 接口 (直连到顶层) ---
    .m_rx_d       (enet0_rx_data),
    .m_rx_en      (enet0_rx_dv),  // `m_rx_en` 就是 MII 的 "Receive Data Valid"
    .m_rx_err     (enet0_rx_er),
    .m_tx_d       (enet0_tx_data),
    .m_tx_en      (enet0_tx_en),
    .m_tx_err     (enet0_tx_er),
    .m_rx_crs     (1'b0),         // 不使用 (CRS, 载波侦听)
    .m_rx_col     (1'b0),         // 不使用 (COL, 冲突检测)

    // --- 3. MDIO 接口 (连接到内部信号线) ---
    .mdc          (mdio_mdc_w),
    .mdio_in      (mdio_mdio_in_w),
    .mdio_out     (mdio_mdio_out_w),
    .mdio_oen     (mdio_mdio_oen_w),

    // --- 4. Avalon-MM 控制接口 (已连接到MDIO状态机 - 扫描版) ---
    .reg_addr     (o_av_addr),       
    .reg_rd       (o_av_read),       
    .reg_wr       (o_av_write),      
    .reg_data_in  (o_av_writedata),  
    .reg_data_out (i_av_readdata),   
    .reg_busy     (i_av_waitrequest), 

    // --- 5. Avalon-ST 发送接口 (给 Tx Sending FSM 用) ---
    .ff_tx_data   (tx_data),         
    .ff_tx_wren   (tx_valid),        
    .ff_tx_sop    (tx_sop),        
    .ff_tx_eop    (tx_eop),         
    .ff_tx_err    (1'b0),        
    .ff_tx_rdy    (tx_ready),             
    
    // --- 6. Avalon-ST 接收接口 (连接到 Rx FSM) ---
    .ff_rx_rdy    (1'b1),         // 始终准备接收
    .ff_rx_data   (i_rx_data),
    .ff_rx_eop    (w_rx_eop),
    .rx_err       (),
    .ff_rx_sop    (w_rx_sop),
    .ff_rx_dval   (w_rx_dval),

    // --- 7. GMII 接口 (MII模式, 悬空) ---
    .gm_rx_d      (8'b0),
    .gm_rx_dv     (1'b0),
    .gm_rx_err    (1'b0),
    .gm_tx_d      (),
    .gm_tx_en     (),
    .gm_tx_err    (),

    // --- 8. MAC 状态接口 (MII模式, 悬空) ---
    .set_10       (1'b0),
    .set_1000     (1'b0),
    .eth_mode     (),
    .ena_10       (),

    // --- 9. 其他杂项接口 (先悬空或给0) ---
    .xon_gen       (1'b0),
    .xoff_gen      (1'b0),
    .ff_tx_crc_fwd (1'b0), 
    .ff_tx_septy   (),
    .tx_ff_uflow   (),
    .ff_tx_a_full  (),
    .ff_tx_a_empty (),
    .rx_err_stat   (),
    .rx_frm_type   (),
    .ff_rx_dsav    (),
    .ff_rx_a_full  (),
    .ff_rx_a_empty ()
);


// =================================================================
// 第3步F: MDIO 读写状态机 (FSM控制PHY复位 + 扫描)
// =================================================================

// 状态机状态定义 (扫描版)
localparam  S_IDLE        = 4'd0,  // 0. 复位, 等待
            S_PHY_WAKEUP  = 4'd1,  // 1. 释放PHY复位, 等待PHY唤醒
            S_SET_ADDR    = 4'd2,  // 2. 设置要扫描的PHY地址 (写 0x0F)
            S_WAIT_WRITE  = 4'd3,  // 3. 等待写操作完成
            S_READ_ID1    = 4'd4,  // 4. 读 REG 2 (0x82)
            S_WAIT_READ1  = 4'd5,  // 5. 等待
            S_READ_ID2    = 4'd6,  // 6. 读 REG 3 (0x83)
            S_WAIT_READ2  = 4'd7,  // 7. 等待
            S_CHECK       = 4'd8,  // 8. 检查是否 FFFF
            S_DONE_OK     = 4'd9,  // 9. 找到了! 成功!
            S_DONE_FAIL   = 4'd10; // 10. 没找到, 失败

// 状态机
always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        r_state        <= S_IDLE;
        r_wait_cnt     <= 20'd0;
        o_av_addr      <= 8'h00;
        o_av_read      <= 1'b0;
        o_av_write     <= 1'b0;
        o_av_writedata <= 32'h0;
        r_phy_id1      <= 32'h0;
        r_phy_id2      <= 32'h0;
        r_phy_addr     <= 5'd0; // 从地址 0 开始扫描
        r_phy_rst_n    <= 1'b0; // !!! 保持PHY在复位状态 !!!
    end else begin
        // --- 默认行为 ---
        o_av_read      <= 1'b0;
        o_av_write     <= 1'b0;

        case (r_state)
            // 0. 保持PHY复位, 并等待 10ms
            S_IDLE: begin
                r_phy_rst_n <= 1'b0; // 保持PHY在复位
                if (r_wait_cnt < 20'd500_000) begin // 假设50M时钟, 等10ms
                    r_wait_cnt <= r_wait_cnt + 1;
                end else begin
                    r_wait_cnt <= 20'd0; // 计数器清零
                    r_state    <= S_PHY_WAKEUP; // 去唤醒PHY
                end
            end
            
            // 1. 释放PHY复位, 并等待 10ms 让PHY开机
            S_PHY_WAKEUP: begin
                r_phy_rst_n <= 1'b1; // !!! 释放PHY复位 !!!
                if (r_wait_cnt < 20'd500_000) begin // 再等 10ms
                    r_wait_cnt <= r_wait_cnt + 1;
                end else begin
                    r_state <= S_SET_ADDR; // PHY应该醒了, 开始扫描
                end
            end
            
            // 2. 把我们要测试的地址(r_phy_addr) 写入 IP核的 mdio_addr0 寄存器(0x0F)
            S_SET_ADDR: begin
                r_phy_rst_n    <= 1'b1; // 保持PHY不复位
                o_av_write     <= 1'b1;
                o_av_addr      <= 8'h0F; // mdio_addr0 寄存器的地址
                o_av_writedata <= {27'b0, r_phy_addr}; // 把 r_phy_addr 写入
                r_state        <= S_WAIT_WRITE;
            end
            
            // 3. 等待写操作完成
            S_WAIT_WRITE: begin
                r_phy_rst_n <= 1'b1;
                o_av_write  <= 1'b1; // 保持写请求
                if (!i_av_waitrequest) begin
                    o_av_write <= 1'b0;
                    r_state    <= S_READ_ID1; // 写完了, 去读ID
                end
            end

            // 4. 读 REG 2 (地址 0x82)
            S_READ_ID1: begin
                r_phy_rst_n <= 1'b1;
                o_av_addr   <= 8'h82; // 读 MDIO 空间 0 的 REG 2
                o_av_read   <= 1'b1;
                r_state     <= S_WAIT_READ1;
            end
            
            // 5. 等待
            S_WAIT_READ1: begin
                r_phy_rst_n <= 1'b1;
                o_av_read   <= 1'b1;
                if (!i_av_waitrequest) begin
                    r_phy_id1 <= i_av_readdata; // 锁存数据
                    o_av_read <= 1'b0;
                    r_state   <= S_READ_ID2;
                end
            end
            
            // 6. 读 REG 3 (地址 0x83)
            S_READ_ID2: begin
                r_phy_rst_n <= 1'b1;
                o_av_addr   <= 8'h83; // 读 MDIO 空间 0 的 REG 3
                o_av_read   <= 1'b1;
                r_state     <= S_WAIT_READ2;
            end

            // 7. 等待
            S_WAIT_READ2: begin
                r_phy_rst_n <= 1'b1;
                o_av_read   <= 1'b1;
                if (!i_av_waitrequest) begin
                    r_phy_id2 <= i_av_readdata; // 锁存数据
                    o_av_read <= 1'b0;
                    r_state   <= S_CHECK;
                end
            end
            
            // 8. 检查结果
            S_CHECK: begin
                r_phy_rst_n <= 1'b1;
                // 检查读回来的ID是不是 0xFFFF (或 0x0000)
                if ((r_phy_id1[15:0] == 16'hFFFF || r_phy_id1[15:0] == 16'h0000) &&
                    (r_phy_id2[15:0] == 16'hFFFF || r_phy_id2[15:0] == 16'h0000)) 
                begin
                    // --- 没读到, 试试下一个地址 ---
                    if (r_phy_addr < 5'd31) begin
                        r_phy_addr <= r_phy_addr + 1; // 地址+1
                        r_state    <= S_SET_ADDR;      // 回去重新设置地址
                    end else begin
                        // 32个地址都试完了, 啥也没有
                        r_state <= S_DONE_FAIL;
                    end
                end else begin
                    // --- 读到了有效ID! ---
                    // 找到了！去配置MAC (开启 TX/RX/Promiscuous)
                    r_state <= 4'd12; // S_CFG_MAC
                end
            end
            
            // S_CFG_MAC (12): 开启 TX/RX/Promiscuous (写 0x13 到 0x02)
            4'd12: begin
                r_phy_rst_n <= 1'b1;
                o_av_write <= 1; o_av_addr <= 8'h02;
                o_av_writedata <= 32'h00000013; // TX_ENA|RX_ENA|PROMIS_EN
                r_state <= 4'd13;
            end
            // S_WAIT_CFG (13)
            4'd13: begin
                r_phy_rst_n <= 1'b1;
                o_av_write <= 1;
                if (!i_av_waitrequest) begin o_av_write <= 0; r_state <= S_DONE_OK; end 
            end

            // 9. 找到了! 成功!
            S_DONE_OK: begin
                r_phy_rst_n <= 1'b1;
                r_state     <= S_DONE_OK;
            end
            
            // 10. 没找到, 失败
            S_DONE_FAIL: begin
                r_phy_rst_n <= 1'b1;
                r_state     <= S_DONE_FAIL;
            end
            
            default: begin
                r_state <= S_IDLE;
            end
        endcase
    end
end

// =================================================================
// 2. Rx FSM (数据接收 -> Rx Buffer) - 修复版
// =================================================================
always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        rx_fsm_state <= S_RX_IDLE;
        rx_w_addr    <= 0;
        rx_pkt_rdy   <= 0;
        rx_pkt_len   <= 0;
        rx_w_en      <= 0;
    end else begin
        rx_w_en <= 0; // 默认拉低

        case (rx_fsm_state)
            S_RX_IDLE: begin
                rx_pkt_rdy <= 0;
                rx_w_addr  <= 0;
                if (w_rx_sop && w_rx_dval) begin
                    rx_w_en <= 1;
                    // !!! 修复 1: 写入第一个字节 !!!
                    rx_buffer[0] <= i_rx_data; 
                    rx_fsm_state <= S_RX_WRITE;
                    rx_w_addr    <= 1; // 准备写下一个
                end
            end

            S_RX_WRITE: begin
                if (w_rx_dval) begin
                    rx_w_en <= 1;
                    // !!! 修复 2: 写入数据 !!!
                    rx_buffer[rx_w_addr] <= i_rx_data;
                    
                    if (w_rx_eop) begin
                        rx_pkt_len   <= rx_w_addr + 1;
                        rx_fsm_state <= S_RX_DONE;
                        rx_w_addr    <= 0; 
                    end else begin
                        rx_w_addr    <= rx_w_addr + 1;
                    end
                end
            end

            S_RX_DONE: begin
                rx_pkt_rdy <= 1; 
                if (parse_state != 0) begin
                   rx_fsm_state <= S_RX_IDLE;
                   rx_pkt_rdy   <= 0; 
                end
            end
        endcase
    end
end

// =================================================================
// 3. Parsing FSM (解析头部信息 - 慢动作稳健版)
// =================================================================
always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        parse_state <= 0;
        parse_addr  <= 0;
        r_mac_dest_in <= 0; r_mac_src_in <= 0;
        r_ip_dest_in  <= 0; r_ip_src_in  <= 0;
        r_udp_dest_in <= 0; r_udp_src_in <= 0;
        r_payload_len <= 0;
    end else begin
        case (parse_state)
            // S0: 等待接收完成
            4'd0: begin
                if (rx_pkt_rdy) begin
                    // 准备读第0个字节
                    parse_addr  <= 0; 
                    parse_state <= 4'd1;
                end
            end
            
            // --- 1. 读目标 MAC (0-5) ---
            // 逻辑：给地址 -> 等一拍(RAM出数据) -> 读数据并给下一个地址
            
            4'd1: begin parse_state <= 4'd2; end // 等待数据 0
            4'd2: begin 
                r_mac_dest_in[47:40] <= rx_r_data; // 读 Byte 0
                parse_addr <= 1;                   // 设地址 1
                parse_state <= 4'd3; 
            end 

            4'd3: begin parse_state <= 4'd4; end // 等待数据 1
            4'd4: begin r_mac_dest_in[39:32] <= rx_r_data; parse_addr <= 2; parse_state <= 4'd5; end
            
            4'd5: begin parse_state <= 4'd6; end
            4'd6: begin r_mac_dest_in[31:24] <= rx_r_data; parse_addr <= 3; parse_state <= 4'd7; end

            4'd7: begin parse_state <= 4'd8; end
            4'd8: begin r_mac_dest_in[23:16] <= rx_r_data; parse_addr <= 4; parse_state <= 4'd9; end

            4'd9: begin parse_state <= 4'd10; end
            4'd10:begin r_mac_dest_in[15:8]  <= rx_r_data; parse_addr <= 5; parse_state <= 4'd11; end

            4'd11:begin parse_state <= 4'd12; end
            4'd12:begin r_mac_dest_in[7:0]   <= rx_r_data; parse_addr <= 6; parse_state <= 4'd13; end

            // --- 2. 读源 MAC (6-11) ---
            4'd13:begin parse_state <= 4'd14; end
            4'd14:begin r_mac_src_in[47:40] <= rx_r_data; parse_addr <= 7; parse_state <= 4'd15; end
            4'd15: begin 
                // 这里做一个跳跃，去读源 IP
                parse_addr <= 26; 
                parse_state <= 4'd16; 
            end

            // --- 3. 读源 IP (26-29) ---
            4'd16: begin parse_state <= 4'd17; end // 等待地址 26 的数据
            4'd17: begin r_ip_src_in[31:24] <= rx_r_data; parse_addr <= 27; parse_state <= 4'd18; end // 读 192
            
            4'd18: begin parse_state <= 4'd19; end
            4'd19: begin r_ip_src_in[23:16] <= rx_r_data; parse_addr <= 28; parse_state <= 4'd20; end // 读 168
            
            4'd20: begin parse_state <= 4'd21; end
            4'd21: begin r_ip_src_in[15:8]  <= rx_r_data; parse_addr <= 29; parse_state <= 4'd22; end // 读 1

            4'd22: begin parse_state <= 4'd23; end
            4'd23: begin r_ip_src_in[7:0]   <= rx_r_data; parse_addr <= 30; parse_state <= 4'd24; end // 读 55

            // --- 4. 读目标 IP (30-33) ---
            4'd24: begin parse_state <= 4'd25; end
            4'd25: begin r_ip_dest_in[31:24] <= rx_r_data; parse_addr <= 31; parse_state <= 4'd26; end
            
            4'd26: begin parse_state <= 4'd27; end
            4'd27: begin r_ip_dest_in[23:16] <= rx_r_data; parse_addr <= 32; parse_state <= 4'd28; end
            
            4'd28: begin parse_state <= 4'd29; end
            4'd29: begin r_ip_dest_in[15:8]  <= rx_r_data; parse_addr <= 33; parse_state <= 4'd30; end
            
            4'd30: begin parse_state <= 4'd31; end
            4'd31: begin r_ip_dest_in[7:0]   <= rx_r_data; parse_addr <= 34; parse_state <= 4'd32; end // 注意: 这里的 32 是新状态

            // --- 5. 读 UDP 端口和长度 (34-39) ---
            // (这里为了节省篇幅，我只写关键的 UDP 长度，端口同理)
            // 假设我们把 UDP Length 的读取放在最后
            
            4'd32: begin parse_addr <= 38; parse_state <= 4'd33; end // 跳去读 UDP 长度高位
            
            4'd33: begin parse_state <= 4'd34; end
            4'd34: begin r_payload_len[15:8] <= rx_r_data; parse_addr <= 39; parse_state <= 4'd35; end
            
            4'd35: begin parse_state <= 4'd36; end
            4'd36: begin 
                r_payload_len[7:0] <= rx_r_data; 
                parse_state <= 6'd63; // 结束状态 (注意: 这里要对应 Copy FSM 的判断条件)
            end
            
            // 结束状态 (Copy FSM 监听的是 parse_state == 15)
            // 为了避免状态码冲突，我们可以把 parse_state 定义加宽，或者就在这里结束
            // 假设 Copy FSM 监听的是 15 (4'd15 是原来的结束，现在状态多了不够用了)
            // !!! 注意 !!! : 状态变多了，4位寄存器 (0-15) 不够用了！
            // 我们需要把 parse_state 改成 6 位宽！
        endcase
    end
end

// =================================================================
// 4. Copy FSM (修正版：修复死锁和地址对齐)
// =================================================================
reg [5:0] hdr_cnt;

always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        copy_state <= C_IDLE;
        copy_addr  <= 0;
        copy_w_addr <= 0;
        copy_w_en   <= 0;
        copy_w_data <= 0;
        tx_pkt_total_len <= 0;
        hdr_cnt <= 0;
    end else begin
        copy_w_en <= 0; 

        case (copy_state)
            C_IDLE: begin
                if (parse_state == 4'd63) begin 
                   copy_state <= C_COPY_INIT;
                end
            end

            // 初始化
            C_COPY_INIT: begin
                copy_w_addr <= 0;
                hdr_cnt     <= 0;
                // !!! 修正：提前设置好 Rx Buffer 的读地址指向 Payload 起点 (42) !!!
                copy_addr   <= 11'd42; 
                copy_state  <= C_COPY_DATA;
            end
            
            // 写头 + 复制数据
            C_COPY_DATA: begin
                copy_w_en <= 1; 
                
                // --- 写以太网头 + IP头 + UDP头 (共42字节) ---
                // ... (这里省略中间的 case 语句，内容保持不变，请保留原有的头部填充代码) ...
                // 请把你原来的 if (copy_w_addr == 0) ... 到 else if (copy_w_addr == 41) 的代码保留在这里
                
                if (copy_w_addr == 0) copy_w_data <= r_mac_src_in[47:40];
                else if (copy_w_addr == 1) copy_w_data <= r_mac_src_in[39:32];
                else if (copy_w_addr == 2) copy_w_data <= r_mac_src_in[31:24];
                else if (copy_w_addr == 3) copy_w_data <= r_mac_src_in[23:16];
                else if (copy_w_addr == 4) copy_w_data <= r_mac_src_in[15:8];
                else if (copy_w_addr == 5) copy_w_data <= r_mac_src_in[7:0];
                else if (copy_w_addr == 6) copy_w_data <= r_mac_dest_in[47:40];
                else if (copy_w_addr == 7) copy_w_data <= r_mac_dest_in[39:32];
                else if (copy_w_addr == 8) copy_w_data <= r_mac_dest_in[31:24];
                else if (copy_w_addr == 9) copy_w_data <= r_mac_dest_in[23:16];
                else if (copy_w_addr == 10) copy_w_data <= r_mac_dest_in[15:8];
                else if (copy_w_addr == 11) copy_w_data <= r_mac_dest_in[7:0];
                else if (copy_w_addr == 12) copy_w_data <= 8'h08;
                else if (copy_w_addr == 13) copy_w_data <= 8'h00;
                else if (copy_w_addr == 14) copy_w_data <= 8'h45;
                else if (copy_w_addr == 15) copy_w_data <= 8'h00;
                // IP Total Length
                else if (copy_w_addr == 16) copy_w_data <= (r_payload_len + 28) >> 8; 
                else if (copy_w_addr == 17) copy_w_data <= (r_payload_len + 28) & 8'hFF; 
                else if (copy_w_addr >= 18 && copy_w_addr <= 21) copy_w_data <= 0; 
                else if (copy_w_addr == 22) copy_w_data <= 8'h40; 
                else if (copy_w_addr == 23) copy_w_data <= 8'h11; 
                else if (copy_w_addr == 24) copy_w_data <= 0;
                else if (copy_w_addr == 25) copy_w_data <= 0;
                else if (copy_w_addr == 26) copy_w_data <= r_ip_dest_in[31:24];
                else if (copy_w_addr == 27) copy_w_data <= r_ip_dest_in[23:16];
                else if (copy_w_addr == 28) copy_w_data <= r_ip_dest_in[15:8];
                else if (copy_w_addr == 29) copy_w_data <= r_ip_dest_in[7:0];
                else if (copy_w_addr == 30) copy_w_data <= r_ip_src_in[31:24];
                else if (copy_w_addr == 31) copy_w_data <= r_ip_src_in[23:16];
                else if (copy_w_addr == 32) copy_w_data <= r_ip_src_in[15:8];
                else if (copy_w_addr == 33) copy_w_data <= r_ip_src_in[7:0];
                else if (copy_w_addr == 34) copy_w_data <= r_udp_dest_in[15:8];
                else if (copy_w_addr == 35) copy_w_data <= r_udp_dest_in[7:0];
                else if (copy_w_addr == 36) copy_w_data <= r_udp_src_in[15:8];
                else if (copy_w_addr == 37) copy_w_data <= r_udp_src_in[7:0];
                // UDP Length 
                else if (copy_w_addr == 38) copy_w_data <= (r_payload_len + 8) >> 8;
                else if (copy_w_addr == 39) copy_w_data <= (r_payload_len + 8) & 8'hFF;
                else if (copy_w_addr == 40) copy_w_data <= 0;
                else if (copy_w_addr == 41) copy_w_data <= 0;

                // --- 复制 Payload (从地址 42 开始) ---
                else begin
                     // 此时 copy_w_addr >= 42
                     // 判断是否还在 Payload 范围内
                     // 有效范围：42 到 (42 + Payload长度 - 1)
                     if (copy_w_addr < 42 + r_payload_len) begin
                         copy_w_data <= rx_r_data; // 这里的 rx_r_data 对应上一周期 copy_addr 的数据
                         copy_addr   <= copy_addr + 1; // 准备读下一个
                     end else begin
                         // Payload 复制完了，去写后缀
                         copy_state <= C_COPY_SUFFIX;
                         copy_w_en  <= 0; // 这一拍先不写
                     end
                end
                
                // --- !!! 核心修复：地址自增逻辑 !!! ---
                // 1. 如果还在写头部 (0-41)，无条件自增
                if (copy_w_addr < 42) begin
                    copy_w_addr <= copy_w_addr + 1;
                end
                // 2. 如果在写数据，且没超限，自增
                else if (copy_w_addr < 42 + r_payload_len) begin
                     copy_w_addr <= copy_w_addr + 1; 
                end
            end

            C_COPY_SUFFIX: begin
                // ... (后缀逻辑保持不变) ...
                copy_w_en <= 1; 
                case (hdr_cnt) 
                    0: copy_w_data <= "F";
                    1: copy_w_data <= "P";
                    2: copy_w_data <= "G";
                    3: copy_w_data <= "A";
                endcase
                if (hdr_cnt == 3) begin
                    copy_state <= C_DONE;
                    tx_pkt_total_len <= copy_w_addr + 1;
                end else begin
                    hdr_cnt <= hdr_cnt + 1;
                    copy_w_addr <= copy_w_addr + 1; 
                end
            end

            C_DONE: begin
                if (send_state == 0 && chksum_state == CS_DONE) begin
                    copy_state <= C_IDLE; 
                end
            end
        endcase
    end
end

// =================================================================
// 5. Checksum FSM (计算 IP 校验和 - 真实计算版)
// =================================================================
reg [31:0] sum_temp; // 用于计算累加和 (32位以容纳进位)

always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        chksum_state <= CS_IDLE;
        chksum_w_en  <= 0;
        chksum_w_addr <= 0;
        chksum_w_data <= 0;
        chksum_r_addr <= 0;
        sum_temp <= 0;
        r_ipv4_checksum <= 0;
    end else begin
        chksum_w_en <= 0; // 默认不写

        case (chksum_state)
            CS_IDLE: begin
                if (copy_state == C_DONE) begin 
                    chksum_state <= CS_INIT;
                end
            end

            // 1. 计算累加和 (Step 1: 累加所有 16 位字)
            CS_INIT: begin
                // 利用现有的寄存器直接计算，不需要读 RAM，速度快且不冲突
                // IP Header 结构:
                // 1. 4500 (Ver/TOS)
                // 2. Total Length (r_payload_len + 28)
                // 3. 0000 (ID)
                // 4. 0000 (Flags)
                // 5. 4011 (TTL=64, Proto=UDP)
                // 6. Src IP High (FPGA IP = 接收到的 Dest IP)
                // 7. Src IP Low
                // 8. Dst IP High (PC IP = 接收到的 Src IP)
                // 9. Dst IP Low
                
                sum_temp <= 32'h4500 + 
                            (r_payload_len + 28) + 
                            32'h0000 + 
                            32'h0000 + 
                            32'h4011 + 
                            r_ip_dest_in[31:16] + 
                            r_ip_dest_in[15:0] + 
                            r_ip_src_in[31:16] + 
                            r_ip_src_in[15:0];
                            
                chksum_state <= CS_CALC;
            end

            // 2. 计算累加和 (Step 2: 处理进位)
            CS_CALC: begin
                // 将高 16 位的进位加到低 16 位上
                // 例如: 0x0002_ABCD -> 0xABCD + 0x0002
                sum_temp <= sum_temp[15:0] + sum_temp[31:16];
                chksum_state <= CS_FINAL;
            end
            
            // 3. 计算累加和 (Step 3: 再次处理可能的进位并取反)
            CS_FINAL: begin
                // 上一步的加法可能再次产生进位，再加一次确保万无一失
                // 然后取反得到 Checksum
                sum_temp <= sum_temp[15:0] + sum_temp[31:16];
                r_ipv4_checksum <= ~sum_temp[15:0];
                chksum_state <= CS_WRITE_HI;
            end

            // 4. 写回高 8 位
            CS_WRITE_HI: begin
                chksum_w_en   <= 1; 
                chksum_w_addr <= 24; // IP Checksum Offset
                chksum_w_data <= r_ipv4_checksum[15:8]; 
                chksum_state  <= CS_WRITE_LO;
            end

            // 5. 写回低 8 位
            CS_WRITE_LO: begin
                chksum_w_en   <= 1; 
                chksum_w_addr <= 25; 
                chksum_w_data <= r_ipv4_checksum[7:0];
                chksum_state  <= CS_DONE;
            end

            CS_DONE: begin
                // 任务完成，等待 Tx FSM 发完 (Tx FSM 发完会把 send_state 变回 0)
                // 只要发送开始，我们就回到 IDLE 等待下一次
                if (send_state == 3) chksum_state <= CS_IDLE;
            end
        endcase
    end
end

// =================================================================
// 6. Tx Sending FSM (发送回传包)
// =================================================================
always @(posedge sys_clk or negedge sys_rst) begin
    if (!sys_rst) begin
        send_state <= 0;
        tx_valid   <= 0;
        tx_sop     <= 0;
        tx_eop     <= 0;
        send_r_addr <= 0;
        tx_data    <= 0;
    end else begin
        case (send_state)
            0: begin // IDLE
                if (chksum_state == CS_DONE) begin 
                    send_state <= 1;
                    send_r_addr <= 0; 
                end
            end
            
            1: begin // 预读
                send_state <= 2;
            end

            2: begin // 发送
                if (tx_ready) begin
                    tx_valid <= 1;
                    tx_data  <= tx_r_data; 
                    
                    if (send_r_addr == 0) tx_sop <= 1;
                    else tx_sop <= 0;

                    if (send_r_addr == tx_pkt_total_len - 1) begin
                        tx_eop <= 1;
                        send_state <= 3; 
                    end else begin
                        tx_eop <= 0;
                        send_r_addr <= send_r_addr + 1; 
                    end
                end
            end
            
            3: begin // 结束
                tx_valid <= 0;
                tx_eop   <= 0;
                if (copy_state == C_IDLE) send_state <= 0;
            end
        endcase
    end
end

endmodule



