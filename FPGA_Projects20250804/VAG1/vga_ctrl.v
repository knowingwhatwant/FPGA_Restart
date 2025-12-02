module vga_ctrl
#(  // 1. 参数列表 (默认给 640x480 的参数，方便实例化时修改)
    parameter H_ACTIVE = 640,
    parameter H_FP     = 16,
    parameter H_SYNC   = 96,
    parameter H_BP     = 48,
    parameter H_TOTAL  = 800, 
    // ... 纵向参数请补全 ...
    parameter V_ACTIVE = 480,
    parameter V_FP     = 10,
    parameter V_SYNC   = 2,
    parameter V_BP     = 33,
    parameter V_TOTAL  = 525
)
(
    // --- 1. 系统输入 ---
    input  wire       clk_pixel,  // 像素时钟 (外部PLL生成好的)
    input  wire       rst_n,

    // --- 2. 也是最重要的：用户交互接口 ---
    output wire [11:0] pixel_x,   // 当前正在画第几列？
    output wire [11:0] pixel_y,   // 当前正在画第几行？
    
    // 用户把颜色算好，传回给模块
    input  wire [23:0] pixel_data_in, // 假设是 RGB888

    // --- 3. 物理接口 (连接到顶层管脚) ---
    output reg        vga_hs,
    output reg        vga_vs,
    output reg [7:0] vga_r,
    output reg [7:0] vga_g,
    output reg [7:0] vga_b,
    
    // ADV7123 专用信号
    output wire       vga_blank_n,
    output wire       vga_sync_n,
    output wire       vga_clk
);


reg [11:0] h_cnt; // 水平计数器
reg [11:0] v_cnt; // 垂直计数器

// 行扫描计数
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        h_cnt <= 0;
    end else begin
        if (h_cnt == H_TOTAL - 1) h_cnt <= 0;
        else                     h_cnt <= h_cnt + 1;
	 end
end

// 列扫描计数
always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) begin
        v_cnt <= 0;
    end else if (h_cnt == H_TOTAL - 1) begin
        if (v_cnt == V_TOTAL - 1) v_cnt <= 0;
        else                       v_cnt <= v_cnt + 1;
    end
end

// 信号同步

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) vga_hs <= 1'b1;
    else if (h_cnt < H_SYNC) vga_hs <= 1'b0; // 起始，同步时脉冲拉低
    else vga_hs <= 1'b1;
end

always @(posedge clk_pixel or negedge rst_n) begin
    if (!rst_n) vga_vs <= 1'b1;
    else if (v_cnt < V_SYNC) vga_vs <= 1'b0; // 起始，同步时脉冲拉低
    else vga_vs <= 1'b1;
end


// 有效区判断
wire h_active = (h_cnt >= H_SYNC + H_BP ) && (h_cnt < H_TOTAL - H_FP );
wire v_active = (v_cnt >= V_SYNC + V_BP ) && (v_cnt < V_TOTAL - V_FP );
wire video_active = h_active && v_active;

// DAC芯片信号
assign vga_blank_n = video_active; 
assign vga_sync_n  = 1'b0; // 或 1'b1
assign vga_clk     = clk_pixel; // 

// 算出坐标输出
assign pixel_x = video_active ? (h_cnt - (H_SYNC + H_BP) ) : 12'd0;
assign pixel_y = video_active ? (v_cnt - (V_SYNC + V_BP) ) : 12'd0;

// 输出颜色
always @(posedge clk_pixel) begin
    if (video_active) begin
        // 如果在显示区，把用户的输入传给物理管脚
        vga_r <= pixel_data_in[23:16];
        vga_g <= pixel_data_in[15: 8];
        vga_b <= pixel_data_in[ 7: 0];
    end else begin
        // 如果在消隐区，强制全黑！
        vga_r <= 0;
        vga_g <= 0;
        vga_b <= 0;
    end
end


endmodule