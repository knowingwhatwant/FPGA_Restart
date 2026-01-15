/*****************************************************************************
 * 文件名: tse_loopback_logic.v
 * 功能: TSE 接收与原样发送环回 (修复 RAM 延迟导致的错位问题)
 *****************************************************************************/

module tse_loopback_logic (
    input           clk,
    input           rst_n,

    // --- TSE RX 接口 (输入) ---
    input  wire [7:0] tse_rx_data,
    input  wire       tse_rx_dv,
    input  wire       tse_rx_sop,
    input  wire       tse_rx_eop,

    // --- RAM 写入控制 (输出) ---
    output reg  [10:0] rx_ram_w_addr,
    output reg         rx_ram_w_en,
    
    // --- RAM 读取控制 (输入/输出) ---
    input  wire [7:0]  rx_ram_r_data,  // RAM 读出的数据 (注意：有1clk延迟)
    output reg  [10:0] rx_ram_r_addr,

    // --- TSE TX 接口 (输出) ---
    output reg  [7:0]  tse_tx_data,
    output reg         tse_tx_wren,
    output reg         tse_tx_sop,
    output reg         tse_tx_eop,
    input  wire        tse_tx_ready,

    output wire  [3:0]  debug_state



);

// --- 状态机定义 ---
localparam S_IDLE      = 4'd0;
localparam S_RX_STORE  = 4'd1;
localparam S_TX_PRE    = 4'd2; // 新增：预读状态
localparam S_TX_STREAM = 4'd3;

reg [3:0]  state;
reg [3:0]  next_state;
reg [10:0] pkt_len; 
reg [10:0] cnt;

assign debug_state = state;
// ============================================================
// 1. 状态机时序逻辑
// ============================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else        state <= next_state;
end

// ============================================================
// 2. 状态机组合逻辑 (控制状态跳转)
// ============================================================
always @(*) begin
    next_state = state; // 默认保持

    case (state)
        S_IDLE: begin
            if (tse_rx_sop) 
                next_state = S_RX_STORE;
        end
        
        S_RX_STORE: begin
            // 接收完毕，进入发送流程
            if (tse_rx_eop) 
                next_state = S_TX_PRE; // 先去预读！
        end

        S_TX_PRE: begin
            // 这是一个过渡状态，用于让 RAM 输出第0个数据
            // 只要 TX 准备好了，就进入流发送
            if (tse_tx_ready) 
                next_state = S_TX_STREAM;
        end

        S_TX_STREAM: begin
            // 发送完最后一个字节后返回 IDLE
            if (tse_tx_ready && (cnt == pkt_len - 1'b1)) 
                next_state = S_IDLE;
        end

        default: next_state = S_IDLE;
    endcase
end

// ============================================================
// 3. 控制信号输出逻辑
// ============================================================
always @(*) begin
    // 默认值
    rx_ram_w_en = 1'b0;
    tse_tx_wren = 1'b0;
    tse_tx_sop  = 1'b0;
    tse_tx_eop  = 1'b0;
    tse_tx_data = 8'd0;

    case (state)
        S_IDLE: begin
            if (tse_rx_sop) rx_ram_w_en = 1'b1; // 写 SOP
        end

        S_RX_STORE: begin
            if (tse_rx_dv)  rx_ram_w_en = 1'b1; // 写数据
        end

        // S_TX_PRE 状态不产生任何使能信号，只用于等待 RAM 地址生效

        S_TX_STREAM: begin
            if (tse_tx_ready) begin
                tse_tx_wren = 1'b1;
                
                // 关键：直接把 RAM 读出的数据赋给 TX
                // 因为我们在 PRE 状态已经给了地址 0，现在 r_data 就是地址 0 的数据
                tse_tx_data = rx_ram_r_data;

                // 标记包头
                if (cnt == 11'd0) 
                    tse_tx_sop = 1'b1;
                
                // 标记包尾
                if (cnt == pkt_len - 1'b1) 
                    tse_tx_eop = 1'b1;
            end
        end
    endcase
end

// ============================================================
// 4. 计数器与地址逻辑
// ============================================================

// --- 写入地址和长度统计 ---
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_ram_w_addr <= 11'd0;
        pkt_len       <= 11'd0;
    end else begin
        // 优先级 1: 在 IDLE 状态检测到 SOP
        // 动作: 这里的 w_addr 是为【下一拍】准备的。
        // 当前拍(IDLE)已经写了地址0，下一拍(RX_STORE)应该写地址1。
        if (state == S_IDLE && tse_rx_sop) begin
            rx_ram_w_addr <= 11'd1; // [修复] 预置为 1
            pkt_len       <= 11'd1; // 当前已经收了 1 个字节
        end 
        // 优先级 2: 在 RX_STORE 状态正常接收
        else if (state == S_RX_STORE && tse_rx_dv) begin
            rx_ram_w_addr <= rx_ram_w_addr + 1'b1;
            pkt_len       <= pkt_len + 1'b1;
        end 
        // 优先级 3: 回到 IDLE 清零 (且没有 SOP 时)
        else if (state == S_IDLE) begin
            rx_ram_w_addr <= 11'd0;
            pkt_len       <= 11'd0;
        end
    end
end

// --- 读取地址和发送计数器 ---
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_ram_r_addr <= 11'd0;
        cnt           <= 11'd0;
    end else begin
        case (state)
            S_IDLE: begin
                rx_ram_r_addr <= 11'd0;
                cnt           <= 11'd0;
            end
            
            S_TX_PRE: begin
                // 关键步骤：在预读状态，地址指向 0，cnt 保持 0
                rx_ram_r_addr <= 11'd0;
                cnt           <= 11'd0;
                
                // 这里有一个小技巧：如果想让流水线动起来，
                // 可以在准备跳转到 STREAM 的那一拍把地址 +1
                if (tse_tx_ready) 
                     rx_ram_r_addr <= 11'd1; // 预取下一个地址
            end

            S_TX_STREAM: begin
                if (tse_tx_ready) begin
                    // 正常计数
                    if (cnt < pkt_len - 1'b1) begin
                        cnt <= cnt + 1'b1;
                        // 地址总是超前数据一拍
                        rx_ram_r_addr <= rx_ram_r_addr + 1'b1; 
                    end
                end
            end
        endcase
    end
end

endmodule