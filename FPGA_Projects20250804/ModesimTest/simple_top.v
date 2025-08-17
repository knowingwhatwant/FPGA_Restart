module simple_top (
    input        clk,      // 系统时钟（50MHz）
    input        rst_n,    // 系统复位（低电平有效）
    output [3:0] led_out   // LED输出（连接计数器输出）
);

// 内部信号：连接子模块的中间信号（可观测）
wire [3:0] count_wire;

// 实例化子模块（计数器）
counter_sub u_counter (
    .clk      (clk),       // 时钟连接
    .rst_n    (rst_n),     // 复位连接
    .count_out(count_wire) // 计数器输出连接到内部wire
);

// 顶层输出：将计数器值映射到LED
assign led_out = count_wire;

endmodule