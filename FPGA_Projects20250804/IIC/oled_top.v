module oled_top(
    input  wire       clk,      // 50MHz
    input  wire       rst_n,    // 外部复位
    output wire       i2c_sclk,
    inout  wire       i2c_sdat
);

    // 内部连接信号
    wire        wrreg_req;
    wire [15:0] addr;
    wire [7:0]  wrdata;
    wire [7:0]  device_id = 8'h78; // OLED 写地址
    wire        rw_done;
    wire        ack_error;

    // 1. 实例化应用层：控制初始化和显示内容
    oled_app_ctrl u_oled_app (
        .clk        (clk),
        .rst_n      (rst_n),
        .wrreg_req  (wrreg_req),
        .addr       (addr),
        .wrdata     (wrdata),
        .rw_done    (rw_done)
    );

    // 2. 实例化协议层：处理寄存器写时序
    i2c_control u_i2c_ctrl (
        .Clk        (clk),
        .Rst_n      (rst_n),
        .wrreg_req  (wrreg_req),
        .rdreg_req  (1'b0),      // OLED 通常只写不读
        .addr       (addr),
        .addr_mode  (1'b0),      // 16位地址模式或根据你的i2c_control调整
        .wrdata     (wrdata),
        .device_id  (device_id),
        .RW_Done    (rw_done),
        .ack        (ack_error),
        .i2c_sclk   (i2c_sclk),
        .i2c_sdat   (i2c_sdat)
    );

endmodule