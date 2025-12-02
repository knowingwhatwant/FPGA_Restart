module vga_1080p_test(
    input  wire       clk_148m5,  // 必须是 148.5 MHz 的时钟！
    input  wire       rst_n,      // 复位
    
    output reg        vga_hsync,
    output reg        vga_vsync,
    output reg [23:0] vga_rgb     // 假设是 RGB888 (24位)，如果是其他位宽请自行截取
);

    // ==========================================
    // 1. 参数定义 (1920x1080 @ 60Hz)
    // ==========================================
    // 水平方向 (Horizontal)
    parameter H_ACTIVE    = 1920;
    parameter H_FP        = 88;
    parameter H_SYNC      = 44;
    parameter H_BP        = 148;
    parameter H_TOTAL     = 2200; // 1920+88+44+148
    
    // 垂直方向 (Vertical)
    parameter V_ACTIVE    = 1080;
    parameter V_FP        = 4;
    parameter V_SYNC      = 5;
    parameter V_BP        = 36;
    parameter V_TOTAL     = 1125; // 1080+4+5+36

    // ==========================================
    // 2. 计数器逻辑
    // ==========================================
    reg [11:0] h_cnt; // 2200 需要 12位 (2^12=4096)
    reg [11:0] v_cnt; // 1125 需要 11位，为了统一用12位

    // 行计数器
    always @(posedge clk_148m5 or negedge rst_n) begin
        if (!rst_n) h_cnt <= 12'd0;
        else if (h_cnt == H_TOTAL - 1) h_cnt <= 12'd0;
        else h_cnt <= h_cnt + 1'b1;
    end

    // 场计数器
    always @(posedge clk_148m5 or negedge rst_n) begin
        if (!rst_n) v_cnt <= 12'd0;
        else if (h_cnt == H_TOTAL - 1) begin
            if (v_cnt == V_TOTAL - 1) v_cnt <= 12'd0;
            else v_cnt <= v_cnt + 1'b1;
        end
    end

    // ==========================================
    // 3. 生成同步信号 (Sync)
    // ==========================================
    // 这里的时序结构： Sync -> Back Porch -> Active -> Front Porch
    // 注意：VGA标准中，Sync脉冲通常是极性可配的，1080p通常习惯 正极性 或 负极性
    // 这里我们按照通用标准，脉冲期间拉高 (Positive Polarity) 或者 拉低。
    // 多数1080p显示器自适应，但标准通常建议 Sync 期间为 High (对于某些时序)
    // 既然是 VGA 接口，我们还是沿用传统的“低电平有效”最保险。
    
    always @(posedge clk_148m5 or negedge rst_n) begin
        if (!rst_n) vga_hsync <= 1'b1;
        else if (h_cnt < H_SYNC) vga_hsync <= 1'b0; // 脉冲拉低
        else vga_hsync <= 1'b1;
    end

    always @(posedge clk_148m5 or negedge rst_n) begin
        if (!rst_n) vga_vsync <= 1'b1;
        else if (v_cnt < V_SYNC) vga_vsync <= 1'b0; // 脉冲拉低
        else vga_vsync <= 1'b1;
    end

    // ==========================================
    // 4. 定义有效显示区 (Active Area)
    // ==========================================
    // 坐标修正：减去 Sync 和 Back Porch 的时间
    wire active_area;
    wire [11:0] x_pos;
    wire [11:0] y_pos;
    
    assign active_area = (h_cnt >= (H_SYNC + H_BP)) && (h_cnt < (H_TOTAL - H_FP)) &&
                         (v_cnt >= (V_SYNC + V_BP)) && (v_cnt < (V_TOTAL - V_FP));
                         
    // 如果你想用坐标做特效，可以用这两个变量
    assign x_pos = active_area ? (h_cnt - (H_SYNC + H_BP)) : 12'd0;
    assign y_pos = active_area ? (v_cnt - (V_SYNC + V_BP)) : 12'd0;

    // ==========================================
    // 5. 颜色循环逻辑 (每 1 秒换个颜色)
    // ==========================================
    reg [27:0] timer_cnt;     // 1秒计时器
    reg [1:0]  color_state;   // 0:红, 1:绿, 2:蓝

    // 148.5MHz 时钟下，数 148,500,000 下就是 1 秒
    always @(posedge clk_148m5 or negedge rst_n) begin
        if (!rst_n) begin
            timer_cnt <= 0;
            color_state <= 0;
        end else begin
            if (timer_cnt >= 148_500_000 - 1) begin
                timer_cnt <= 0;
                if (color_state == 2) color_state <= 0;
                else color_state <= color_state + 1'b1;
            end else begin
                timer_cnt <= timer_cnt + 1'b1;
            end
        end
    end

    // ==========================================
    // 6. 输出 RGB
    // ==========================================
    always @(posedge clk_148m5) begin
        if (!active_area) begin
            vga_rgb <= 24'h000000; // 消隐区必须全黑
        end else begin
            case (color_state)
                2'd0: vga_rgb <= 24'hFF0000; // 红 (R=FF, G=00, B=00)
                2'd1: vga_rgb <= 24'h00FF00; // 绿
                2'd2: vga_rgb <= 24'h0000FF; // 蓝
                default: vga_rgb <= 24'hFFFFFF;
            endcase
        end
    end

endmodule