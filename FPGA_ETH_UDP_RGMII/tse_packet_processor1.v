// ============================================================================
// Module: tse_packet_processor (Fixed RX/TX Alignment)
// Description: 修复了接收和发送的地址对齐问题，确保首字节不丢失
// ============================================================================

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

    // --- 脉冲控制接口 ---
    output reg        pulse_start_trig,
    output reg [15:0] pulse_target_val,

    // --- Debug ---
    output wire [ 3:0] debug_state,
    output wire [10:0] debug_cnt,
    output wire [10:0] debug_pkt_len
);

  // FPGA 信息定义 (MAC: 02:00:00:00:00:01, IP: 192.168.1.123)
  localparam FPGA_MAC_0 = 8'h02; localparam FPGA_MAC_1 = 8'h00;
  localparam FPGA_MAC_2 = 8'h00; localparam FPGA_MAC_3 = 8'h00;
  localparam FPGA_MAC_4 = 8'h00; localparam FPGA_MAC_5 = 8'h01;
  localparam FPGA_IP_0  = 8'hC0; localparam FPGA_IP_1  = 8'hA8;
  localparam FPGA_IP_2  = 8'h01; localparam FPGA_IP_3  = 8'h7B;

  // 状态机定义
  localparam S_IDLE      = 0;  // 空闲状态：等待接收新数据包的起始信号（SOP）
  localparam S_RX_STORE  = 1;  // 接收存储状态：将接收到的数据逐字节写入 RX RAM，直到包结束（EOP）
  localparam S_PROC_CALC = 2;  // 处理计算状态：根据当前字节位置（cnt）计算需读取的 RX RAM 地址（用于修改 MAC/IP 等字段）
  localparam S_PROC_WAIT = 3;  // 处理等待状态：等待 RAM 读出数据稳定（应对 RAM 的 1 拍延迟）
  localparam S_PROC_BUFF = 4;  // 处理锁存状态：锁存从 RX RAM 读出的数据，并根据需要修改（如替换 MAC、IP、清零校验和、解析指令）
  localparam S_PROC_WR   = 5;  // 处理写入状态：将处理后的数据写入 TX RAM，准备发送
  localparam S_TX_PRE    = 6;  // 发送预置状态：初始化 TX RAM 读地址，等待 TSE TX FIFO 准备就绪
  localparam S_TX_STREAM = 7;  // 发送流状态：从 TX RAM 读取数据并逐字节发送至 TSE TX 接口，直至整包发送完毕

  reg [3:0]  state, next_state;
  reg [10:0] pkt_len;
  reg [10:0] cnt;

  assign debug_state = state;
  assign debug_cnt   = cnt;
  assign debug_pkt_len = pkt_len;

 
// 解决“后一拍才置1”的问题：
    // 当在 IDLE 状态检测到 SOP 时，立即拉高写使能，让下一个上升沿直接把当前数据写入地址 0
    assign rx_ram_w_en   = (state == S_IDLE && tse_rx_sop) || (state == S_RX_STORE && tse_rx_dv);
    
    // 地址逻辑：如果是起始包，强制指向 0，否则跟随内部计数器
    assign rx_ram_w_addr = (state == S_IDLE && tse_rx_sop) ? 11'd0 : r_rx_w_addr;
    
    // 数据直接透传
    assign rx_ram_w_data = tse_rx_data;



  // 1. 状态跳转逻辑
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else state <= next_state;
  end

  always @(*) begin
    next_state = state;
    case (state)
      S_IDLE:      if (tse_rx_sop) next_state = S_RX_STORE;
      S_RX_STORE:  if (tse_rx_eop) next_state = S_PROC_CALC;
      S_PROC_CALC: next_state = S_PROC_WAIT;
      S_PROC_WAIT: next_state = S_PROC_BUFF;
      S_PROC_BUFF: next_state = S_PROC_WR;
      S_PROC_WR:   if (cnt == pkt_len - 1) next_state = S_TX_PRE;
                   else next_state = S_PROC_CALC;
      S_TX_PRE:    if (tse_tx_ready) next_state = S_TX_STREAM;
      S_TX_STREAM: if (tse_tx_ready && (cnt == pkt_len - 1)) next_state = S_IDLE;
      default:     next_state = S_IDLE;
    endcase
  end

  // 2. 接收与计数逻辑 (修复对齐)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_ram_w_addr <= 0;
      rx_ram_w_en   <= 0;
      pkt_len       <= 0;
    end else begin
      rx_ram_w_en <= 0;
      if (state == S_IDLE && tse_rx_sop) begin
        rx_ram_w_en   <= 1;
        rx_ram_w_addr <= 1;
        pkt_len       <= 1;
      end else if (state == S_RX_STORE && tse_rx_dv) begin
        rx_ram_w_en   <= 1;
        rx_ram_w_addr <= rx_ram_w_addr + 1;
        pkt_len       <= pkt_len + 1;
      end
    end
  end

  // 3. 统一计数器
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) cnt <= 0;
    else begin
      case (state)
        S_PROC_WR:   cnt <= (cnt < pkt_len - 1) ? cnt + 1 : 0;
        S_TX_STREAM: if (tse_tx_ready) cnt <= (cnt < pkt_len - 1) ? cnt + 1 : 0;
        S_IDLE, S_TX_PRE: cnt <= 0;
        default: cnt <= cnt;
      endcase
    end
  end

  // 4. 处理与读取逻辑
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) rx_ram_r_addr <= 0;
    else if (state == S_PROC_CALC) begin
      // 交换 MAC/IP 逻辑 (基于地址 0 对齐)
      if (cnt >= 0 && cnt <= 5)       rx_ram_r_addr <= cnt + 6; 
      else if (cnt >= 30 && cnt <= 33) rx_ram_r_addr <= cnt - 4;
      else                            rx_ram_r_addr <= cnt;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_ram_w_data <= 0; tx_ram_w_en <= 0; tx_ram_w_addr <= 0;
      pulse_start_trig <= 0; pulse_target_val <= 0;
    end else begin
      tx_ram_w_en <= 0;
      pulse_start_trig <= 0;
      if (state == S_PROC_BUFF) begin
        if (cnt == 6)        tx_ram_w_data <= FPGA_MAC_0;
        else if (cnt == 7)   tx_ram_w_data <= FPGA_MAC_1;
        else if (cnt == 8)   tx_ram_w_data <= FPGA_MAC_2;
        else if (cnt == 9)   tx_ram_w_data <= FPGA_MAC_3;
        else if (cnt == 10)  tx_ram_w_data <= FPGA_MAC_4;
        else if (cnt == 11)  tx_ram_w_data <= FPGA_MAC_5;
        else if (cnt == 26)  tx_ram_w_data <= FPGA_IP_0;
        else if (cnt == 27)  tx_ram_w_data <= FPGA_IP_1;
        else if (cnt == 28)  tx_ram_w_data <= FPGA_IP_2;
        else if (cnt == 29)  tx_ram_w_data <= FPGA_IP_3;
        else if (cnt == 40 || cnt == 41) tx_ram_w_data <= 8'h00;
        else                 tx_ram_w_data <= rx_ram_r_data;
        
        if (cnt == 42 && rx_ram_r_data >= 8'h31 && rx_ram_r_data <= 8'h39) begin
            pulse_start_trig <= 1;
            pulse_target_val <= (rx_ram_r_data - 8'h30) * 16'd200;
        end
      end
      if (state == S_PROC_WR) begin
        tx_ram_w_en   <= 1;
        tx_ram_w_addr <= cnt;
      end
    end
  end

  // 5. 发送逻辑 (修复 TX 对齐)
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tx_ram_r_addr <= 0;
    else begin
      if (state == S_IDLE) 
        tx_ram_r_addr <= 0;
      else if (state == S_TX_PRE && tse_tx_ready) 
        tx_ram_r_addr <= 1; 
      else if (state == S_TX_STREAM && tse_tx_ready && cnt < pkt_len - 1) 
        tx_ram_r_addr <= tx_ram_r_addr + 1;
    end
  end

  always @(*) begin
    tse_tx_wren = 0; tse_tx_sop = 0; tse_tx_eop = 0; tse_tx_data = 0;
    if (state == S_TX_STREAM && tse_tx_ready) begin
      tse_tx_wren = 1;
      tse_tx_data = tx_ram_r_data;
      if (cnt == 0)           tse_tx_sop = 1;
      if (cnt == pkt_len - 1) tse_tx_eop = 1;
    end
  end

endmodule