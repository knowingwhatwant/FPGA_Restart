`timescale 1ns / 1ps

module tb_iic_driver();

    // ==========================================
    // 1. 信号定义
    // ==========================================
    reg        clk;
    reg        rst_n;
    reg        cmd_start;
    reg  [7:0] cmd_data;
    wire       cmd_done;
    
    wire       iic_scl;
    wire       iic_sda;

    // ==========================================
    // 2. 例化被测模块 (DUT)
    // ==========================================
    iic_driver u_iic_driver (
        .clk       (clk),
        .rst_n     (rst_n),
        .cmd_start (cmd_start),
        .cmd_data  (cmd_data),
        .cmd_done  (cmd_done),
        .iic_scl   (iic_scl),
        .iic_sda   (iic_sda)
    );

    // ==========================================
    // 3. 模拟上拉电阻 (关键!)
    // ==========================================
    // I2C 总线是开漏输出，如果没有上拉，高阻态(z)在波形里就是红线或不可定。
    // pullup 原语告诉仿真器：如果没人驱动这根线，就自动把它拉高。
    pullup(iic_sda); 

    // ==========================================
    // 4. 时钟生成 (50MHz)
    // ==========================================
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // 周期 20ns -> 50MHz
    end

    // ==========================================
    // 5. 虚拟从机逻辑 (模拟 OLED 回复 ACK)
    // ==========================================
    reg slave_ack_en; // 从机是否要回复ACK
    
    // 这里的逻辑是：只在需要ACK的时候，把 SDA 强行拉低
    // 否则保持高阻态(z)，让 pullup 电阻或 主机 去控制
    assign iic_sda = slave_ack_en ? 1'b0 : 1'bz;

    initial begin
        slave_ack_en = 0;
        
        // 永远循环，检测总线状态
        forever begin
            // 等待 START 信号 (SCL高时，SDA下降沿)
            @(negedge iic_sda);
            if (iic_scl == 1) begin
                // 检测到 START 了！准备接收8位数据
                // 等待 8 个 SCL 脉冲 (8位数据发送完毕)
                repeat(9) @(negedge iic_scl);
                
                // --- 现在是第 9 个周期的开始 (ACK 阶段) ---
                // 主机释放总线，从机(TB) 必须拉低 SDA 表示 ACK
                slave_ack_en = 1; 
                
                // 等待 ACK 时钟周期结束 (SCL 再次变低)
                @(negedge iic_scl);
                
                // --- ACK 结束 ---
                slave_ack_en = 0; // 从机松手
            end
        end
    end

    // ==========================================
    // 6. 激励序列 (Main Test)
    // ==========================================
    initial begin
        // --- 初始化 ---
        rst_n = 0;
        cmd_start = 0;
        cmd_data = 0;
        #200; // 等待复位稳定
        rst_n = 1;
        #200;
        
        // --- 测试用例 1: 发送数据 0xA5 (1010_0101) ---
        // 这个数据很好，0和1交替，方便看波形
        $display("Test Case 1: Sending 0xA5...");
        cmd_data = 8'hA5; 
        cmd_start = 1;   // 给一个脉冲
        #20;             // 脉冲持续一个时钟周期即可
        cmd_start = 0;

        // 等待发送完成 (done 信号变高)
        @(posedge cmd_done);
        $display("Test Case 1: Done!");
        
        #5000; // 休息一会儿

        // --- 测试用例 2: 发送数据 0x3C (OLED 地址) ---
        $display("Test Case 2: Sending 0x3C...");
        cmd_data = 8'h3C;
        cmd_start = 1;
        #20;
        cmd_start = 0;

        @(posedge cmd_done);
        $display("Test Case 2: Done!");

        #2000;
        $stop; // 停止仿真
    end

endmodule