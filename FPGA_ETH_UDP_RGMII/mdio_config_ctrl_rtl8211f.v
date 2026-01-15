// ============================================================================
// Module: mdio_config_ctrl_rtl8211f (Corrected Version)
// Description: 修正了数据捕获逻辑，确保 MDIO 读取的每一项数据都能被正确暂存
// ============================================================================

module mdio_config_ctrl_rtl8211f (
    input  wire        clk,
    input  wire        rst_n,

    // --- Avalon-MM Master 接口 ---
    output reg  [7:0]  o_av_addr,
    output reg         o_av_read,
    output reg         o_av_write,
    output reg  [31:0] o_av_writedata,
    input  wire [31:0] i_av_readdata,
    input  wire        i_av_waitrequest,

    // --- 控制与状态 ---
    output reg         o_phy_rst_n,
    output reg [15:0]  r_phy_id1,
    output reg [15:0]  r_phy_id2,
    output reg         o_cfg_done
);

    // 状态机定义
    localparam  S_IDLE          = 4'd0,
                S_PHY_WAKEUP    = 4'd1,
                S_SET_ADDR      = 4'd2,
                S_READ_ID1      = 4'd3,
                S_WAIT_ID1      = 4'd4, // 专门等待并捕获 ID1
                S_READ_ID2      = 4'd5,
                S_WAIT_ID2      = 4'd6, // 专门等待并捕获 ID2
                S_SOFT_RESET    = 4'd7,
                S_SWITCH_PAGE   = 4'd8,
                S_SET_DELAY     = 4'd9,
                S_BACK_PAGE0    = 4'd10,
                S_CFG_MAC       = 4'd11,
                S_DONE_OK       = 4'd12,
                S_WAIT_WRITE    = 4'd13; // 专门用于等待写入完成的通用状态

    reg [3:0]   r_state;
    reg [3:0]   r_next_state;
    reg [23:0]  r_wait_cnt;
    reg [4:0]   r_phy_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state        <= S_IDLE;
            r_wait_cnt     <= 0;
            o_av_read      <= 0;
            o_av_write     <= 0;
            r_phy_addr     <= 5'd4; // 从你的硬件地址 4/5 开始扫
            o_phy_rst_n    <= 0;
            r_phy_id1      <= 0;
            r_phy_id2      <= 0;
            o_cfg_done     <= 0;
        end else begin
            o_av_read  <= 0;
            o_av_write <= 0;

            case (r_state)
                S_IDLE: begin
                    o_phy_rst_n <= 0;
                    if (r_wait_cnt < 24'd1_000_000) r_wait_cnt <= r_wait_cnt + 1;
                    else begin r_wait_cnt <= 0; r_state <= S_PHY_WAKEUP; end
                end

                S_PHY_WAKEUP: begin
                    o_phy_rst_n <= 1;
                    if (r_wait_cnt < 24'd2_500_000) r_wait_cnt <= r_wait_cnt + 1;
                    else begin r_wait_cnt <= 0; r_state <= S_SET_ADDR; end
                end

                // --- 1. 设置物理地址 ---
                S_SET_ADDR: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h0F;
                    o_av_writedata <= {27'b0, r_phy_addr};
                    r_next_state   <= S_READ_ID1;
                    r_state        <= S_WAIT_WRITE;
                end

                // --- 2. 读取 ID1 (Reg 2) ---
                S_READ_ID1: begin
                    o_av_read <= 1;
                    o_av_addr <= 8'h82;
                    r_state   <= S_WAIT_ID1;
                end

                S_WAIT_ID1: begin
                    o_av_read <= 1;
                    if (!i_av_waitrequest) begin
                        r_phy_id1 <= i_av_readdata[15:0]; // 关键：在这里立即抓取数据
                        o_av_read <= 0;
                        r_state   <= S_READ_ID2;
                    end
                end

                // --- 3. 读取 ID2 (Reg 3) ---
                S_READ_ID2: begin
                    o_av_read <= 1;
                    o_av_addr <= 8'h83;
                    r_state   <= S_WAIT_ID2;
                end

                S_WAIT_ID2: begin
                    o_av_read <= 1;
                    if (!i_av_waitrequest) begin
                        r_phy_id2 <= i_av_readdata[15:0]; // 关键：在这里立即抓取数据
                        o_av_read <= 0;
                        r_state   <= S_SOFT_RESET;
                    end
                end

                // --- 4. 校验与复位 ---
                S_SOFT_RESET: begin
                    // 校验是否为 RTL8211F
                    // ID1: 0x001C (Realtek OUI)
                    // ID2: 0xC91x (Model 0x11, Revision varies, e.g., 0xC916)
                    // 使用掩码 (r_phy_id2 & 16'hFFF0) == 16'hC910 忽略 Revision 差异
                    if (r_phy_id1 == 16'h001C && (r_phy_id2 & 16'hFFF0) == 16'hC910) begin
                        o_av_write     <= 1;
                        o_av_addr      <= 8'h80;
                        o_av_writedata <= 32'h8000;
                        r_next_state   <= S_SWITCH_PAGE;
                        r_state        <= S_WAIT_WRITE;
                    end else if (r_phy_addr < 5'd31) begin
                        r_phy_addr <= r_phy_addr + 1;
                        r_state    <= S_SET_ADDR;
                    end else begin
                        r_phy_addr <= 0;
                        r_state    <= S_SET_ADDR;
                    end
                end

                // --- 5. 切页配置延时 (Page 0xd08, Reg 17) ---
                S_SWITCH_PAGE: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h9F; // Reg 31
                    o_av_writedata <= 32'h0D08;
                    r_next_state   <= S_SET_DELAY;
                    r_state        <= S_WAIT_WRITE;
                end

                S_SET_DELAY: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h91; // Reg 17
                    o_av_writedata <= 32'h0003; // 开启 TX/RX Delay
                    r_next_state   <= S_BACK_PAGE0;
                    r_state        <= S_WAIT_WRITE;
                end

                // --- 6. 切回 Page 0 并配置 MAC ---
                S_BACK_PAGE0: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h9F;
                    o_av_writedata <= 32'h0000;
                    r_next_state   <= S_CFG_MAC;
                    r_state        <= S_WAIT_WRITE;
                end

                S_CFG_MAC: begin
                    o_av_write     <= 1;
                    o_av_addr      <= 8'h02;
                    o_av_writedata <= 32'h0000000B;
                    r_next_state   <= S_DONE_OK;
                    r_state        <= S_WAIT_WRITE;
                end

                // 通用写入等待
                S_WAIT_WRITE: begin
                    o_av_write <= 1;
                    if (!i_av_waitrequest) begin
                        o_av_write <= 0;
                        r_state    <= r_next_state;
                    end
                end

                S_DONE_OK: begin
                    o_cfg_done <= 1;
                    r_state    <= S_DONE_OK;
                end

                default: r_state <= S_IDLE;
            endcase
        end
    end

endmodule