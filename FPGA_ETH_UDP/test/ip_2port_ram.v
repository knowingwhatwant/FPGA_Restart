module ip_2port_ram(
    input      clk,
    input      rst_n
);

// 内部信号
wire        ram_wr_en;
wire [10:0] ram_wr_addr;
wire [7:0]  ram_wr_data;
wire        wr_done_sig; // 桥梁：写完信号

wire        ram_rd_en;
wire [10:0] ram_rd_addr;
wire [7:0]  ram_rd_data;

// --------------------------------------------------------
// 1. RAM写模块
// --------------------------------------------------------
ram_wr ram_wr_inst(
    .clk         (clk),
    .rst_n       (rst_n),
    .ram_wr_en   (ram_wr_en),
    .ram_wr_addr (ram_wr_addr),
    .ram_wr_data (ram_wr_data),
    .wr_done     (wr_done_sig)  // 输出：我写完了
);

// --------------------------------------------------------
// 2. RAM读模块
// --------------------------------------------------------
ram_rd ram_rd_inst(
    .clk         (clk),
    .rst_n       (rst_n),
    .rd_start    (wr_done_sig), // 输入：等写完再开始
    .ram_rd_en   (ram_rd_en),
    .ram_rd_addr (ram_rd_addr),
    .ram_rd_data (ram_rd_data)
);

// --------------------------------------------------------
// 3. 双端口RAM IP核 (完全匹配你的新端口定义)
// --------------------------------------------------------
ram_2port_2048 ram_2_inst(
    .clock     (clk),
    
    // --- Port A (作为写入口) ---
    .address_a (ram_wr_addr),
    .data_a    (ram_wr_data),
    .wren_a    (ram_wr_en),   // 写使能：由写模块控制
    .rden_a    (1'b0),        // 读使能：Port A 不读，置0
    .q_a       (),            // 读出数据：悬空

    // --- Port B (作为读取口) ---
    .address_b (ram_rd_addr),
    .data_b    (8'd0),        // 写入数据：Port B 不写，置0
    .wren_b    (1'b0),        // 写使能：Port B 不写，置0
    .rden_b    (ram_rd_en),   // 读使能：由读模块控制 (关键！)
    .q_b       (ram_rd_data)  // 读出数据：连接到观测信号
);

endmodule