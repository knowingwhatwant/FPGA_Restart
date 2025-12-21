`timescale 1ns / 1ps

module tb_i2c_bit_shift();

    // ---------------------------------------------------------
    // 1. 信号定义
    // ---------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [5:0]  cmd;
    reg         go;
    reg  [7:0]  tx_data;
    wire [7:0]  rx_data;
    wire        trans_done;
    wire        ack_o;
    wire        i2c_sclk;
    
    // 关键：使用 tri1 模拟物理上拉电阻，解决波形“乱跳”和白虚线问题
    tri1        i2c_sdat; 

    // 命令常量
    localparam WR = 6'b000001, STA = 6'b000010, STO = 6'b001000;

    // ---------------------------------------------------------
    // 2. 模块实例化
    // ---------------------------------------------------------
    i2c_bit_shift u_dut (
        .Clk        (clk),
        .Rst_n      (rst_n),
        .Cmd        (cmd),
        .Go         (go),
        .Rx_DATA    (rx_data),
        .Tx_DATA    (tx_data),
        .Trans_Done (trans_done),
        .ack_o      (ack_o),
        .i2c_sclk   (i2c_sclk),
        .i2c_sdat   (i2c_sdat)
    );

    // ---------------------------------------------------------
    // 3. 时钟与复位
    // ---------------------------------------------------------
    initial clk = 0;
    always #10 clk = ~clk; // 50MHz

    // ---------------------------------------------------------
    // 4. 严谨的从机模拟逻辑 (Slave Model)
    // ---------------------------------------------------------
    reg slave_en;
    assign i2c_sdat = slave_en ? 1'b0 : 1'bz; // 仅输出 0 或释放

    initial begin
        slave_en = 0;
        forever begin
            // A. 等待起始位：SCLK 为高时 SDA 出现下降沿
            @(negedge i2c_sdat);
            if (i2c_sclk == 1'b1) begin
                // B. 接收 8 个位：数 8 个 SCLK 下降沿
                repeat(8) @(negedge i2c_sclk);
                
                // C. 边界条件：在第 8 位下降沿立即拉低，模拟从机给出 ACK
                slave_en = 1; 
                
                // D. 维持整个第 9 位周期，直到其下降沿释放
                @(negedge i2c_sclk);
                slave_en = 0;
            end
        end
    end

    // ---------------------------------------------------------
    // 5. 激励过程 (主状态机模拟)
    // ---------------------------------------------------------
    initial begin
        // 初始化信号
        rst_n = 0; cmd = 0; go = 0; tx_data = 0;
        #200;
        rst_n = 1;
        #500;

        // --- 任务 1: 写地址 0x78 (STA + WR) ---
        // 模拟上层控制层：数据和命令必须在 Go 之前稳定
        @(posedge clk);
        tx_data <= 8'h78;
        cmd     <= STA | WR;
        go      <= 1'b1;
        @(posedge clk);
        go      <= 1'b0; // Go 必须是脉冲

        // 等待底层汇报收工
        wait(trans_done);
        #500;

        // --- 任务 2: 写控制字 0x00 (仅 WR) ---
        @(posedge clk);
        tx_data <= 8'h00;
        cmd     <= WR;
        go      <= 1'b1;
        @(posedge clk);
        go      <= 1'b0;
        
        wait(trans_done);
        #500;

        // --- 任务 3: 写数据 0xAF + 停止位 (WR + STO) ---
        @(posedge clk);
        tx_data <= 8'hAF;
        cmd     <= WR | STO;
        go      <= 1'b1;
        @(posedge clk);
        go      <= 1'b0;

        wait(trans_done);
        
        #5000;
        $display("Simulation Success!");
        $stop;
    end

endmodule