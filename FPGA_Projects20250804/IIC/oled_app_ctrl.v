module oled_app_ctrl(
    input  wire        clk,
    input  wire        rst_n,
    output reg         wrreg_req,
    output reg  [15:0] addr,      // 高8位决定命令(00)或数据(40)
    output reg  [7:0]  wrdata,
    input  wire        rw_done
);

    // 状态机状态
    localparam IDLE      = 3'd0;
    localparam INIT      = 3'd1;  // 执行初始化序列
    localparam CLEAR     = 3'd2;  // 清屏逻辑
    localparam TEST_DATA = 3'd3;  // 显示测试点阵
    localparam DONE      = 3'd4;

    reg [2:0] state;
    reg [5:0] step;           // 步骤计数器
    reg [12:0] clear_cnt;      // 清屏计数器 (128x64/8 = 1024字节)
    reg [31:0] delay_cnt;

    // 根据 STM32 代码整理的完整初始化序列
    reg [7:0] init_seq [27:0];
    initial begin
        init_seq[0] = 8'hAE; // 关闭显示
        init_seq[1] = 8'hD5; init_seq[2] = 8'h80; // 设置时钟分频
        init_seq[3] = 8'hA8; init_seq[4] = 8'h3F; // 设置多路复用率
        init_seq[5] = 8'hD3; init_seq[6] = 8'h00; // 设置显示偏移
        init_seq[7] = 8'h40; // 设置起始行
        init_seq[8] = 8'h8D; init_seq[9] = 8'h14; // ★使能电荷泵 (必须)
        init_seq[10]= 8'h20; init_seq[11]= 8'h02; // ★页地址模式
        init_seq[12]= 8'hA1; // 段重映射 (左右反置)
        init_seq[13]= 8'hC8; // COM扫描方向 (上下反置)
        init_seq[14]= 8'hDA; init_seq[15]= 8'h12; // COM硬件配置
        init_seq[16]= 8'h81; init_seq[17]= 8'hCF; // 亮度对比度
        init_seq[18]= 8'hD9; init_seq[19]= 8'hF1; // 充电周期
        init_seq[20]= 8'hDB; init_seq[21]= 8'h30; // VCOMH
        init_seq[22]= 8'hA4; // 全屏显示开启
        init_seq[23]= 8'hA6; // 正常显示
        init_seq[24]= 8'hB0; // 设置页地址为0
        init_seq[25]= 8'h00; // 设置列地址低位
        init_seq[26]= 8'h10; // 设置列地址高位
        init_seq[27]= 8'hAF; // 开启显示
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= IDLE;
            wrreg_req <= 0;
            step <= 0;
            delay_cnt <= 0;
            clear_cnt <= 0;
        end else begin
            case(state)
                IDLE: begin
                    // 对应 STM32 的 delay_ms(500)
                    if(delay_cnt < 50_000_000) // 1秒延迟确保上电稳定
                        delay_cnt <= delay_cnt + 1;
                    else begin
                        delay_cnt <= 0;
                        state <= INIT;
                    end
                end

                INIT: begin
                    if(step <= 27) begin
                        addr <= 16'h0000;      // 发送命令
                        wrdata <= init_seq[step];
                        wrreg_req <= 1;
                        if(rw_done) begin
                            wrreg_req <= 0;
                            step <= step + 1;
                        end
                    end else begin
                        state <= CLEAR;
                        step <= 0;
                    end
                end

                CLEAR: begin
                    // 模拟 STM32 的 OLED_Clear()
                    // 需要填满 8 页 x 128 列 = 1024 字节的数据 0x00
                    if(clear_cnt < 1024) begin
                        addr <= 16'h4000;      // 发送显示数据
                        wrdata <= 8'h00;
                        wrreg_req <= 1;
                        if(rw_done) begin
                            wrreg_req <= 0;
                            clear_cnt <= clear_cnt + 1;
                        end
                    end else begin
                        state <= TEST_DATA;
                    end
                end

                TEST_DATA: begin
                    // 测试：在屏幕起始位置画一段白线
                    addr <= 16'h4000;
                    wrdata <= 8'hFF; 
                    wrreg_req <= 1;
                    if(rw_done) begin
                        wrreg_req <= 0;
                        state <= DONE;
                    end
                end

                DONE: state <= DONE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule