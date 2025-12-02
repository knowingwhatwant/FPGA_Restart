module top_vga(
    input  wire       sys_clk,    // 板载 50MHz
    input  wire       sys_rst_n,  // 复位按键
    
    output wire       vga_hs,
    output wire       vga_vs,
    // 假设你板子是 RGB565 (16bit)，我们需要把 24位 截断给它
    output wire [7:0] vga_r,
    output wire [7:0] vga_g,
    output wire [7:0] vga_b,

    output wire vga_blank_n,
    output wire vga_sync_n,
    output wire vga_clk
);

    wire clk_25_175m; // 像素时钟
    wire locked;    // PLL 锁定信号
    wire rst_n_safe;
    
    // 1. 实例化 PLL / Clock Wizard
    clk_wiz_1080p u_pll (
        .inclk0     (sys_clk),
        .c0         (clk_25_175m),
        .locked     (locked)      // 只有当时钟稳定了，locked 才会变高
    );
    
    assign rst_n_safe = sys_rst_n & locked;
    

    wire [11:0] x_pos;
    wire [11:0] y_pos;
    wire [23:0] color_data;

    vga_ctrl u_vga ( 
    .clk_pixel(clk_25_175m),  // 像素时钟 (外部PLL生成好的)
    .rst_n(sys_rst_n),
    .pixel_x(x_pos),           
    .pixel_y(y_pos),           
    .pixel_data_in(color_data),     
    .vga_hs(vga_hs),
    .vga_vs(vga_vs),
    .vga_r(vga_r),
    .vga_g(vga_g),
    .vga_b(vga_b),
    .vga_blank_n(vga_blank_n),
    .vga_sync_n(vga_sync_n),
    .vga_clk(vga_clk)             
    );
    
    assign color_data = x_pos[7:0] + y_pos[7:0];
    // assign color_data = (x_pos >= 100 && x_pos < 200 && y_pos >= 100 && y_pos < 200) 
    //                     ? 24'hFF0000   // 画一个 100x100 的红方块
    //                     : 24'h0000FF;  // 其他地方是蓝色

endmodule