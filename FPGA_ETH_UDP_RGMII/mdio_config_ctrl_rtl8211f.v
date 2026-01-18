// ============================================================================
// Module: mdio_config_ctrl_rtl8211f
// Description: RTL8211F PHY 配置状态机，严格遵循 Canvas 手册标准序列
// 包含: 硬件复位 -> ID校验 -> 软件复位 -> RGMII延时配置 -> TSE MAC配置
// ============================================================================

module mdio_config_ctrl_rtl8211f (
    input  wire        clk,              // 建议 50MHz 系统时钟
    input  wire        rst_n,            // 全局复位

    // --- Avalon-MM Master 接口 (连接至 TSE IP 的寄存器控制端) ---
    output reg  [7:0]  o_av_addr,
    output reg         o_av_read,
    output reg         o_av_write,
    output reg  [31:0] o_av_writedata,
    input  wire [31:0] i_av_readdata,
    input  wire        i_av_waitrequest, // 1表示忙，必须等待

    // --- PHY 状态与控制 ---
    output reg         o_phy_rst_n,      // 连接至物理引脚 enet0_rst_n
    output reg [15:0]  r_phy_id1,        // 用于调试：厂商ID
    output reg [15:0]  r_phy_id2,        // 用于调试：型号ID
    output reg         o_cfg_done        // 配置完成标志
);

    // 状态机状态定义
    localparam  S_IDLE          = 4'd0,  // 硬件复位状态
                S_PHY_WAKEUP    = 4'd1,  // 释放复位等待
                S_SET_ADDR      = 4'd2,  // 选择要访问的 PHY 物理地址
                S_READ_ID1      = 4'd3,  // 读取 ID1
                S_WAIT_ID1      = 4'd4,  
                S_READ_ID2      = 4'd5,  // 读取 ID2
                S_WAIT_ID2      = 4'd6,  
                S_SOFT_RESET    = 4'd7,  // 软件复位指令
                S_RESET_WAIT    = 4'd14, // 软复位后关键等待 (50ms)
                S_SWITCH_PAGE   = 4'd8,  // 切页至 0xd08
                S_SET_DELAY     = 4'd9,  // 配置 TX/RX 延时
                S_BACK_PAGE0    = 4'd10, // 切回 Page 0
                S_CFG_MAC       = 4'd11, // 配置 TSE IP 内部 MAC 参数
                S_DONE_OK       = 4'd12, // 全部完成
                S_WAIT_WRITE    = 4'd13; // 通用写入等待握手状态

    reg [3:0]   r_state;
    reg [3:0]   r_next_state;
    reg [25:0]  r_wait_cnt;              // 50MHz下，26位宽足够计数 > 1秒
    reg [4:0]   r_phy_addr;              // 扫描范围 0-31

    // 时间常量定义 (基于 50MHz 时钟)
    localparam T_20MS = 26'd1_000_000;
    localparam T_50MS = 26'd2_500_000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state        <= S_IDLE;
            r_wait_cnt     <= 0;
            o_av_read      <= 0;
            o_av_write     <= 0;
            o_av_addr      <= 0;
            o_av_writedata <= 0;
            r_phy_addr     <= 5'd4;      // 初始地址建议设为硬件 Strapping 的地址
            o_phy_rst_n    <= 0;
            r_phy_id1      <= 0;
            r_phy_id2      <= 0;
            o_cfg_done     <= 0;
        end else begin
            o_av_read  <= 0;
            o_av_write <= 0;

            case (r_state)
                // --- 阶段 1: 硬件复位 ---
                S_IDLE: begin
                    o_phy_rst_n <= 0;    // 拉低复位引脚
                    if (r_wait_cnt < T_20MS) 
                        r_wait_cnt <= r_wait_cnt + 1;
                    else begin 
                        r_wait_cnt <= 0; 
                        r_state <= S_PHY_WAKEUP; 
                    end
                end

                // --- 阶段 2: 唤醒与电平采样等待 ---
                S_PHY_WAKEUP: begin
                    o_phy_rst_n <= 1;    // 释放复位
                    if (r_wait_cnt < T_50MS) 
                        r_wait_cnt <= r_wait_cnt + 1;
                    else begin 
                        r_wait_cnt <= 0; 
                        r_state <= S_SET_ADDR; 
                    end
                end

                // --- 阶段 3: 地址选择与 ID 确认 ---
                S_SET_ADDR: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h0F; // MDIO_ADDR0 寄存器
                    o_av_writedata <= {27'b0, r_phy_addr};
                    r_next_state   <= S_READ_ID1;
                    r_state        <= S_WAIT_WRITE;
                end

                S_READ_ID1: begin
                    o_av_read <= 1;
                    o_av_addr <= 8'h82;      // 对应 PHY Reg 2
                    r_state   <= S_WAIT_ID1;
                end

                S_WAIT_ID1: begin
                    o_av_read <= 1;
                    if (!i_av_waitrequest) begin
                        r_phy_id1 <= i_av_readdata[15:0];
                        o_av_read <= 0;
                        r_state   <= S_READ_ID2;
                    end
                end

                S_READ_ID2: begin
                    o_av_read <= 1;
                    o_av_addr <= 8'h83;      // 对应 PHY Reg 3
                    r_state   <= S_WAIT_ID2;
                end

                S_WAIT_ID2: begin
                    o_av_read <= 1;
                    if (!i_av_waitrequest) begin
                        r_phy_id2 <= i_av_readdata[15:0];
                        o_av_read <= 0;
                        r_state   <= S_SOFT_RESET;
                    end
                end

                // --- 阶段 4: 软件复位  ---
                S_SOFT_RESET: begin
                    // 校验厂商 ID (0x001C) 和 型号前缀 (0xC91x)
                    if (r_phy_id1 == 16'h001C && (r_phy_id2 & 16'hFFF0) == 16'hC910) begin
                        o_av_write     <= 1;
                        o_av_addr      <= 8'h80; // PHY Reg 0 (BMCR)
                        o_av_writedata <= 32'h8000; // Bit 15: Soft Reset
                        r_next_state   <= S_RESET_WAIT;
                        r_state        <= S_WAIT_WRITE;
                    end else if (r_phy_addr < 5'd31) begin
                        r_phy_addr <= r_phy_addr + 1'b1; // 地址不匹配，继续扫描
                        r_state    <= S_SET_ADDR;
                    end else begin
                        r_phy_addr <= 0; // 全扫描失败，循环尝试
                        r_state    <= S_SET_ADDR;
                    end
                end

                // 软复位后强制等待 50ms (Canvas 建议)
                S_RESET_WAIT: begin
                    if (r_wait_cnt < T_50MS) 
                        r_wait_cnt <= r_wait_cnt + 1;
                    else begin
                        r_wait_cnt <= 0;
                        r_state    <= S_SWITCH_PAGE;
                    end
                end

                // --- 阶段 5: RGMII 延时配置 (Canvas 第3步) ---
                S_SWITCH_PAGE: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h9F; // Reg 31 (Page Select)
                    o_av_writedata <= 32'h0D08; // 进入扩展 Page 0xd08
                    r_next_state   <= S_SET_DELAY;
                    r_state        <= S_WAIT_WRITE;
                end

                S_SET_DELAY: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h91; // Page 0xd08 里的 Reg 17
                    // 0x0003 表示开启 TXC 延时和 RXC 延时 (各约 2ns)
                    // 如果你发现接收稳定但发送不稳定，可以尝试 0x0002
                    o_av_writedata <= 32'h0003; 
                    r_next_state   <= S_BACK_PAGE0;
                    r_state        <= S_WAIT_WRITE;
                end

                S_BACK_PAGE0: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h9F; 
                    o_av_writedata <= 32'h0000; // 回到标准寄存器页
                    r_next_state   <= S_CFG_MAC;
                    r_state        <= S_WAIT_WRITE;
                end

                // --- 阶段 6: TSE MAC 内部配置 (Canvas 第4步) ---
                S_CFG_MAC: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h02; // TSE IP 内部寄存器 command_config
                    // 0x1B = 11011b
                    // Bit 0: TX_ENA (1)
                    // Bit 1: RX_ENA (1)
                    // Bit 3: ETH_SPEED (1) -> 1000Mbps
                    // Bit 4: PROMIS_EN (1) -> 混杂模式，接收所有包
                    o_av_writedata <= 32'h0000001B; 
                    r_next_state   <= S_DONE_OK;
                    r_state        <= S_WAIT_WRITE;
                end

                // --- 通用写入握手状态 ---
                S_WAIT_WRITE: begin
                    o_av_write <= 1; // 保持写信号直到 waitrequest 撤销
                    if (!i_av_waitrequest) begin
                        o_av_write <= 0;
                        r_state    <= r_next_state;
                    end
                end

                S_DONE_OK: begin
                    o_cfg_done <= 1;
                    r_state    <= S_DONE_OK; // 配置完成，原地踏步
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule