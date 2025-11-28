module tse_packet_processor (
    input clk,
    input rst_n,

    // --- TSE RX 接口 ---
    input wire [7:0] tse_rx_data,
    input wire       tse_rx_dv,
    input wire       tse_rx_sop,
    input wire       tse_rx_eop,

    // --- RAM 写入控制 (RX RAM) ---
    output reg [10:0] rx_ram_w_addr,
    output reg        rx_ram_w_en,

    // --- RAM 读取控制 (RX RAM) ---
    input  wire [ 7:0] rx_ram_r_data,
    output reg  [10:0] rx_ram_r_addr,

    // --- RAM 写入控制 (TX RAM) ---
    output reg [10:0] tx_ram_w_addr,
    output reg [ 7:0] tx_ram_w_data,
    output reg        tx_ram_w_en,

    // --- RAM 读取控制 (TX RAM) ---
    input  wire [ 7:0] tx_ram_r_data,
    output reg  [10:0] tx_ram_r_addr,

    // --- TSE TX 接口 ---
    output reg  [7:0] tse_tx_data,
    output reg        tse_tx_wren,
    output reg        tse_tx_sop,
    output reg        tse_tx_eop,
    input  wire       tse_tx_ready,

    // --- 脉冲控制接口 (修改部分) ---
    output reg        pulse_start_trig,  // 脉冲启动触发
    output reg [15:0] pulse_target_val,  // 脉冲目标值


    // --- Debug ---
    output wire [ 3:0] debug_state,
    output wire [10:0] debug_cnt,
    output wire [10:0] debug_pkt_len,
    output wire [ 7:0] debug_rx_ram_r_data_mon
);

  // --- FPGA 本地信息 ---
  localparam FPGA_MAC_0 = 8'h02;
  localparam FPGA_MAC_1 = 8'h00;
  localparam FPGA_MAC_2 = 8'h00;
  localparam FPGA_MAC_3 = 8'h00;
  localparam FPGA_MAC_4 = 8'h00;
  localparam FPGA_MAC_5 = 8'h01;

  localparam FPGA_IP_0 = 8'hC0;  // 192
  localparam FPGA_IP_1 = 8'hA8;  // 168
  localparam FPGA_IP_2 = 8'h01;  // 1
  localparam FPGA_IP_3 = 8'h7B;  // 123

  // --- 状态机定义 (新增 S_PROC_WAIT) ---
  localparam S_IDLE = 0;
  localparam S_RX_STORE = 1;
  localparam S_PROC_CALC = 2;  // 1. 给地址
  localparam S_PROC_WAIT = 3;  // 2. 等RAM (新增!)
  localparam S_PROC_BUFF = 4;  // 3. 锁数据
  localparam S_PROC_WR = 5;  // 4. 写数据
  localparam S_TX_PRE = 6;
  localparam S_TX_STREAM = 7;

  reg [3:0] state, next_state;
  reg [10:0] pkt_len;
  reg [10:0] cnt;

  // Debug
  assign debug_state             = state;
  assign debug_cnt               = cnt;
  assign debug_pkt_len           = pkt_len;
  assign debug_rx_ram_r_data_mon = rx_ram_r_data;

  // ============================================================
  // 1. 状态机时序
  // ============================================================
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else state <= next_state;
  end

  // ============================================================
  // 2. 状态跳转逻辑
  // ============================================================
  always @(*) begin
    next_state = state;
    case (state)
      S_IDLE: if (tse_rx_sop) next_state = S_RX_STORE;

      S_RX_STORE: if (tse_rx_eop) next_state = S_PROC_CALC;

      S_PROC_CALC: next_state = S_PROC_WAIT;  // -> 去等待

      S_PROC_WAIT: next_state = S_PROC_BUFF;  // -> 去锁存

      S_PROC_BUFF: next_state = S_PROC_WR;  // -> 去写入

      S_PROC_WR: begin
        if (cnt == pkt_len - 1'b1) next_state = S_TX_PRE;
        else next_state = S_PROC_CALC;
      end

      S_TX_PRE: if (tse_tx_ready) next_state = S_TX_STREAM;

      S_TX_STREAM: if (tse_tx_ready && (cnt == pkt_len - 1'b1)) next_state = S_IDLE;

      default: next_state = S_IDLE;
    endcase
  end

  // ============================================================
  // 3. 统一计数器
  // ============================================================
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= 0;
    end else begin
      case (state)
        S_IDLE:   cnt <= 0;
        // RX, CALC, WAIT, BUFF 都不动计数器
        S_PROC_WR: begin
          if (cnt < pkt_len - 1'b1) cnt <= cnt + 1'b1;
          else cnt <= 0;
        end
        S_TX_PRE: cnt <= 0;
        S_TX_STREAM: begin
          if (tse_tx_ready && cnt < pkt_len - 1'b1) cnt <= cnt + 1'b1;
        end
        default:  cnt <= cnt;
      endcase
    end
  end

  // ============================================================
  // 4. 接收逻辑 (RX Store)
  // ============================================================
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_ram_w_addr <= 0;
      rx_ram_w_en   <= 0;
      pkt_len       <= 0;
    end else begin
      rx_ram_w_en <= 0;

      if (state == S_IDLE && tse_rx_sop) begin
        rx_ram_w_en   <= 1;
        rx_ram_w_addr <= 11'd1;
        pkt_len       <= 11'd1;
      end else if (state == S_RX_STORE && tse_rx_dv) begin
        rx_ram_w_en   <= 1;
        rx_ram_w_addr <= rx_ram_w_addr + 1'b1;
        pkt_len       <= pkt_len + 1'b1;
      end else if (state == S_IDLE) begin
        rx_ram_w_addr <= 0;
      end
    end
  end

  // ============================================================
  // 5. 处理逻辑 (4步走: 计算->等待->锁存->写)
  // ============================================================

  // 5.1 计算 RX 读地址 (在 CALC 状态更新)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) rx_ram_r_addr <= 0;
    else if (state == S_PROC_CALC) begin
      if (cnt >= 0 && cnt <= 5) rx_ram_r_addr <= cnt + 6;
      else if (cnt >= 30 && cnt <= 33) rx_ram_r_addr <= cnt - 4;
      else rx_ram_r_addr <= cnt;
    end
  end

  // 5.2 锁存数据 (在 BUFF 状态锁存)
  // 经过 CALC(更新地址) -> WAIT(RAM响应) -> BUFF(锁存)，数据绝对稳定
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_ram_w_data    <= 0;
      tx_ram_w_data    <= 0;
      pulse_start_trig <= 0;
      pulse_target_val <= 0;
    end else begin
      // 脉冲触发信号默认是脉冲，只维持一拍，所以这里要拉低
      // 但为了安全，我们可以在状态机跳转时拉低，或者在这里默认拉低
      pulse_start_trig <= 0;
      if (state == S_PROC_BUFF) begin
        // 修改或直通数据
        if (cnt == 6) tx_ram_w_data <= FPGA_MAC_0;
        else if (cnt == 7) tx_ram_w_data <= FPGA_MAC_1;
        else if (cnt == 8) tx_ram_w_data <= FPGA_MAC_2;
        else if (cnt == 9) tx_ram_w_data <= FPGA_MAC_3;
        else if (cnt == 10) tx_ram_w_data <= FPGA_MAC_4;
        else if (cnt == 11) tx_ram_w_data <= FPGA_MAC_5;
        else if (cnt == 26) tx_ram_w_data <= FPGA_IP_0;
        else if (cnt == 27) tx_ram_w_data <= FPGA_IP_1;
        else if (cnt == 28) tx_ram_w_data <= FPGA_IP_2;
        else if (cnt == 29) tx_ram_w_data <= FPGA_IP_3;
        else if (cnt == 40 || cnt == 41) tx_ram_w_data <= 8'h00; // UDP checksum 
        else tx_ram_w_data <= rx_ram_r_data;
      end
      // --- 2. [新增] 指令解析逻辑 ---
      // 检查地址 42 (Payload 第1个字节)
      if (cnt == 42) begin
        // 判断是否为数字 '1' ~ '9' (ASCII 0x31 ~ 0x39)
        if (rx_ram_r_data >= 8'h31 && rx_ram_r_data <= 8'h39) begin
          pulse_start_trig <= 1;  // 触发！

          // 计算公式：(ASCII值 - 0x30) * 200
          // 例如 '2' (0x32) - 0x30 = 2.  2 * 200 = 400.
          pulse_target_val <= (rx_ram_r_data - 8'h30) * 16'd200;
        end
      end
    end
  end

  // 5.3 执行写入 (在 WR 状态写)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_ram_w_en   <= 0;
      tx_ram_w_addr <= 0;
    end else begin
      tx_ram_w_en <= 0;

      if (state == S_PROC_WR) begin
        tx_ram_w_en   <= 1;
        tx_ram_w_addr <= cnt;
      end
    end
  end

  // ============================================================
  // 6. 发送逻辑
  // ============================================================
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tx_ram_r_addr <= 0;
    else begin
      if (state == S_IDLE) tx_ram_r_addr <= 0;
      else if (state == S_TX_PRE && tse_tx_ready) tx_ram_r_addr <= 1;
      else if (state == S_TX_STREAM && tse_tx_ready && cnt < pkt_len - 1'b1) tx_ram_r_addr <= tx_ram_r_addr + 1'b1;
    end
  end

  always @(*) begin
    tse_tx_wren = 0;
    tse_tx_sop  = 0;
    tse_tx_eop  = 0;
    tse_tx_data = 0;

    if (state == S_TX_STREAM && tse_tx_ready) begin
      tse_tx_wren = 1;
      tse_tx_data = tx_ram_r_data;

      if (cnt == 0) tse_tx_sop = 1;
      if (cnt == pkt_len - 1'b1) tse_tx_eop = 1;
    end
  end

endmodule
