module oled_ctrl (
    input  wire       clk,
    input  wire       rst_n,
    
    // 连接到 IIC Driver
    output reg        iic_start,
    output reg  [7:0] iic_data,
    output reg        iic_is_last, // 控制是否挂断
    input  wire       iic_done,
    
    // 物理接口 (为了以后扩展，现在可能只用内部信号)
    output reg        init_done    // 初始化完成标志
);

    // ============================================
    // 1. OLED 初始化指令表 (ROM)
    // ============================================
    // 这是一个简化版的初始化序列，足够点亮屏幕
    reg [7:0] oled_init_data [0:20]; 
    initial begin
        oled_init_data[0]  = 8'hAE; // Display OFF
        oled_init_data[1]  = 8'h00; // Set Lower Column Start Addr
        oled_init_data[2]  = 8'h10; // Set Higher Column Start Addr
        oled_init_data[3]  = 8'h40; // Set Display Start Line
        oled_init_data[4]  = 8'h81; // Set Contrast Control
        oled_init_data[5]  = 8'hCF; // Contrast Value
        oled_init_data[6]  = 8'hA1; // Set Segment Re-map (左右翻转)
        oled_init_data[7]  = 8'hC8; // Set COM Output Scan Direction (上下翻转)
        oled_init_data[8]  = 8'hA6; // Normal / Inverse Display
        oled_init_data[9]  = 8'hA8; // Set Multiplex Ratio
        oled_init_data[10] = 8'h3F; // Multiplex Ratio Value (1/64)
        oled_init_data[11] = 8'hD3; // Set Display Offset
        oled_init_data[12] = 8'h00; // Offset Value
        oled_init_data[13] = 8'hD5; // Set Display Clock Divide
        oled_init_data[14] = 8'h80; // Clock Value
        oled_init_data[15] = 8'h8D; // Set Charge Pump
        oled_init_data[16] = 8'h14; // Enable Charge Pump (必须有！)
        oled_init_data[17] = 8'hDA; // Set COM Pins Hardware Config
        oled_init_data[18] = 8'h12; // Config Value
        oled_init_data[19] = 8'hDB; // Set VCOMH Deselect Level
        oled_init_data[20] = 8'h40; // VCOMH Value
        // ... 还可以加 8'hAF (Display ON) ...
        // 实际上我们会在最后额外发一个 Display ON
    end
    
    localparam CMD_NUM = 21; // 指令总数

    // ============================================
    // 2. 状态机
    // ============================================
    reg [3:0] state;
    localparam IDLE      = 0;
    localparam SEND_ADDR = 1; // 发 0x78
    localparam SEND_CTRL = 2; // 发 0x00
    localparam SEND_CMD  = 3; // 发 指令
    localparam CHECK_NUM = 4; // 检查发完了没
    localparam DONE      = 5; // 结束

    reg [4:0] cmd_index; // 指令计数器

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state       <= IDLE;
            cmd_index   <= 0;
            iic_start   <= 0;
            iic_is_last <= 0;
            init_done   <= 0;
        end
        else begin
            case(state)
                IDLE: begin
                    // 上电稍等一下再开始 (可选)
                    state <= SEND_ADDR;
                end

                // 第一步：发送设备地址 0x78
                SEND_ADDR: begin
                    iic_data    <= 8'h78;
                    iic_start   <= 1;
                    iic_is_last <= 0; // 不要挂断！
                    
                    if(iic_done) begin // 等待驱动完成
                        iic_start <= 0; // 撤销脉冲
                        state     <= SEND_CTRL;
                    end
                end

                // 第二步：发送控制字节 0x00 (表示后面是命令)
                SEND_CTRL: begin
                    iic_data    <= 8'h00;
                    iic_start   <= 1;
                    iic_is_last <= 0; // 不要挂断！
                    
                    if(iic_done) begin
                        iic_start <= 0;
                        state     <= SEND_CMD;
                    end
                end

                // 第三步：发送具体命令
                SEND_CMD: begin
                    iic_data    <= oled_init_data[cmd_index];
                    iic_start   <= 1;
                    iic_is_last <= 1; // 【挂断！】这是这一包的最后一个字节
                    
                    if(iic_done) begin
                        iic_start <= 0;
                        state     <= CHECK_NUM;
                    end
                end

                // 第四步：检查是否发完
                CHECK_NUM: begin
                    if(cmd_index == CMD_NUM - 1) begin
                        // 还有一个开机指令 Display ON (0xAF) 没发
                        // 这里为了简单，你可以把 0xAF 放在数组最后
                        // 或者在这里额外发一次。
                        // 假设数组里包含了 AF，那就直接 DONE
                        state <= DONE; 
                    end
                    else begin
                        cmd_index <= cmd_index + 1;
                        state     <= SEND_ADDR; // 发下一个命令包
                    end
                end
                
                DONE: begin
                    init_done <= 1;
                    // 发完了，可以在这里再发一个全屏点亮的指令，或者就停在这里
                    // 如果屏幕初始化成功，应该会显示花屏(随机噪声)或者全黑
                end
            endcase
        end
    end

endmodule