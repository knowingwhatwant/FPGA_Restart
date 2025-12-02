module vga_driver_xga (
    input  wire       clk_65m,    // 必须是 65MHz
    input  wire       rst_n,
    
    // 这里的输出对应 DE2-115 的物理管脚
    output reg        vga_hs,        // VGA_HS
    output reg        vga_vs,        // VGA_VS
    output wire [7:0] vga_r,         // VGA_R[7:0]
    output wire [7:0] vga_g,         // VGA_G[7:0]
    output wire [7:0] vga_b,         // VGA_B[7:0]
    output wire       vga_blank_n,   // VGA_BLANK_N (新增!)
    output wire       vga_sync_n,    // VGA_SYNC_N  (新增!)
    output wire       vga_clk        // VGA_CLK     (新增!)
);

    // ==========================================
    // 1. 参数定义 (1024x768 @ 60Hz)
    // Pixel Clock = 65.0 MHz
    // ==========================================
    parameter H_ACTIVE    = 1024;
    parameter H_FP        = 24;
    parameter H_SYNC      = 136;
    parameter H_BP        = 160;
    parameter H_TOTAL     = 1344; // 1024+24+136+160
    
    parameter V_ACTIVE    = 768;
    parameter V_FP        = 3;
    parameter V_SYNC      = 6;
    parameter V_BP        = 29;
    parameter V_TOTAL     = 806;  // 768+3+6+29

    // ==========================================
    // 2. 计数器
    // ==========================================
    reg [10:0] h_cnt; // 1344 < 2048 (11bit)
    reg [10:0] v_cnt; // 806  < 1024 (10bit, 但为了安全给11bit)

    always @(posedge clk_65m or negedge rst_n) begin
        if (!rst_n) h_cnt <= 0;
        else if (h_cnt == H_TOTAL - 1) h_cnt <= 0;
        else h_cnt <= h_cnt + 1'b1;
    end

    always @(posedge clk_65m or negedge rst_n) begin
        if (!rst_n) v_cnt <= 0;
        else if (h_cnt == H_TOTAL - 1) begin
            if (v_cnt == V_TOTAL - 1) v_cnt <= 0;
            else v_cnt <= v_cnt + 1'b1;
        end
    end

    // ==========================================
    // 3. 生成同步信号
    // 1024x768 @ 60Hz 标准通常是 负极性 (Negative Polarity)
    // ==========================================
    always @(posedge clk_65m or negedge rst_n) begin
        if (!rst_n) vga_hs <= 1'b1;
        else if (h_cnt < H_SYNC) vga_hs <= 1'b0; // 脉冲拉低
        else vga_hs <= 1'b1;
    end

    always @(posedge clk_65m or negedge rst_n) begin
        if (!rst_n) vga_vs <= 1'b1;
        else if (v_cnt < V_SYNC) vga_vs <= 1'b0; // 脉冲拉低
        else vga_vs <= 1'b1;
    end

    // ==========================================
    // 4. 有效显示区判断 (用于控制 BLANK_N)
    // ==========================================
    wire video_active;
    assign video_active = (h_cnt >= (H_SYNC + H_BP)) && (h_cnt < (H_TOTAL - H_FP)) &&
                          (v_cnt >= (V_SYNC + V_BP)) && (v_cnt < (V_TOTAL - V_FP));

    // ADV7123 关键信号控制
    // 当 video_active 为 1 时，BLANK_N 必须为 1。
    // 当 消隐期 时，BLANK_N 必须为 0。
    assign vga_blank_n = video_active; 
    
    // 不需要 Sync-on-Green，直接拉高
    assign vga_sync_n  = 1'b0; // DE2-115 示例代码通常置0，实际上置1也可以，为了保险参考例程置0 
    
    // 输出时钟给 DAC 芯片
    assign vga_clk = clk_65m; 

    // ==========================================
    // 5. 简单的彩条测试
    // ==========================================
    // 计算当前像素在屏幕上的 X 坐标 (0 ~ 1023)
    wire [10:0] x_pos = video_active ? (h_cnt - (H_SYNC + H_BP)) : 11'd0;
    
    reg [23:0] rgb_data;

    always @(posedge clk_65m) begin
        if (!video_active) begin
            rgb_data <= 24'h000000; // 消隐区给黑
        end else begin
            // 简单的三色竖条
            if (x_pos < 341)      rgb_data <= 24'hFF0000; // 红
            else if (x_pos < 682) rgb_data <= 24'h00FF00; // 绿
            else                  rgb_data <= 24'h0000FF; // 蓝
        end
    end

    // DE2-115 是 24位色 (RGB888)，每个通道8位
    assign vga_r = rgb_data[23:16];
    assign vga_g = rgb_data[15:8];
    assign vga_b = rgb_data[7:0];

endmodule