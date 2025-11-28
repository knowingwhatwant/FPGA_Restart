module ram_verification (
    input  wire        clk,      // 系统时钟
    input  wire        rst_n,    // 复位 (低有效)

    // --- 调试输出 (接LED或SignalTap) ---
    output reg         test_pass,    // 测试通过 (绿灯)
    output reg         test_error,   // 测试失败 (红灯)
    output reg         test_done     // 测试完成
);

    // ============================================================
    // 1. 参数与信号定义
    // ============================================================
    localparam TEST_DEPTH = 2048;    // 测试深度 (0 ~ 2047)

    // RAM 接口信号
    reg  [10:0] addr_a;
    reg  [10:0] addr_b;
    reg  [7:0]  data_a;
    reg  [7:0]  data_b; // Port B 写入数据，本测试不用，置0
    reg         wren_a;
    reg         wren_b; // Port B 写使能，本测试不用，置0
    wire [7:0]  q_a;    // Port A 读出，本测试不用
    wire [7:0]  q_b;    // Port B 读出，用于检查

    // 状态机
    localparam S_IDLE       = 3'd0;
    localparam S_WRITE_LOOP = 3'd1;
    localparam S_READ_INIT  = 3'd2;
    localparam S_READ_ADDR  = 3'd3; // 给出地址
    localparam S_READ_WAIT  = 3'd4; // 等待数据流出
    localparam S_READ_CHECK = 3'd5; // 检查数据
    localparam S_DONE       = 3'd6;

    reg [2:0]  state;
    reg [10:0] cnt;           // 地址计数器
    reg [7:0]  expected_data; // 期望读到的数据

    // SignalTap 防止优化属性
    (* keep = "true" *) wire [2:0]  debug_state = state;
    (* keep = "true" *) wire [10:0] debug_cnt   = cnt;
    (* keep = "true" *) wire [7:0]  debug_q_b   = q_b;

    // ============================================================
    // 2. RAM IP 核例化
    // ============================================================
    ram_2port_2048 u_ram (
        .clock     (clk),
        
        // Port A: 写端口
        .address_a (addr_a),
        .data_a    (data_a),
        .wren_a    (wren_a),
        .q_a       (q_a),
        
        // Port B: 读端口
        .address_b (addr_b),
        .data_b    (data_b),
        .wren_b    (wren_b),
        .q_b       (q_b)
    );

    // ============================================================
    // 3. 验证逻辑主程序
    // ============================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            cnt        <= 0;
            test_pass  <= 0;
            test_error <= 0;
            test_done  <= 0;
            
            // RAM 信号初始化
            addr_a <= 0; data_a <= 0; wren_a <= 0;
            addr_b <= 0; data_b <= 0; wren_b <= 0;
        end else begin
            case (state)
                // -------------------------------------------------
                // IDLE
                // -------------------------------------------------
                S_IDLE: begin
                    cnt <= 0;
                    state <= S_WRITE_LOOP;
                end

                // -------------------------------------------------
                // STEP 1: 写入阶段 (Write Loop)
                // 填充 RAM：地址 0 写 0，地址 1 写 1 ...
                // -------------------------------------------------
                S_WRITE_LOOP: begin
                    wren_a <= 1;
                    addr_a <= cnt;
                    data_a <= cnt[7:0]; // 数据 = 地址的低8位

                    if (cnt == TEST_DEPTH - 1) begin
                        cnt   <= 0;
                        state <= S_READ_INIT; // 写满了，去读
                    end else begin
                        cnt   <= cnt + 1;
                    end
                end

                // -------------------------------------------------
                // STEP 2: 读取初始化
                // 关掉写使能
                // -------------------------------------------------
                S_READ_INIT: begin
                    wren_a <= 0;
                    addr_a <= 0;
                    cnt    <= 0;
                    state  <= S_READ_ADDR;
                end

                // -------------------------------------------------
                // STEP 3: 给出读地址
                // -------------------------------------------------
                S_READ_ADDR: begin
                    addr_b <= cnt; // 向 Port B 请求地址 cnt 的数据
                    state  <= S_READ_WAIT;
                end

                // -------------------------------------------------
                // STEP 4: 等待 RAM 输出 (Latency)
                // RAM 读数通常滞后 1-2 拍，这里显式等待 1 拍
                // -------------------------------------------------
                S_READ_WAIT: begin
                    // 此时 RAM 内部正在锁存地址并输出数据
                    // 期望的数据应该是 cnt 的低8位
                    expected_data <= cnt[7:0]; 
                    state <= S_READ_CHECK;
                end

                // -------------------------------------------------
                // STEP 5: 检查数据
                // -------------------------------------------------
                S_READ_CHECK: begin
                    // 此时 q_b 上应该是有效数据
                    if (q_b !== expected_data) begin
                        test_error <= 1; // 报错！
                        // 为了方便调试，可以在这里卡住，或者继续
                        // 这里选择卡住，方便在 SignalTap 里看到错误现场
                        state <= S_DONE; 
                    end else begin
                        // 数据正确，继续下一个
                        if (cnt == TEST_DEPTH - 1) begin
                            test_pass <= 1; // 全部通过
                            state     <= S_DONE;
                        end else begin
                            cnt   <= cnt + 1;
                            state <= S_READ_ADDR; // 读下一个
                        end
                    end
                end

                // -------------------------------------------------
                // DONE: 结束
                // -------------------------------------------------
                S_DONE: begin
                    test_done <= 1;
                    wren_a    <= 0;
                    // 保持状态不变
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule