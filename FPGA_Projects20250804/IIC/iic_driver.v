module iic_driver (
    input  wire       clk,      
    input  wire       rst_n,
    // --- 控制接口 ---
    input  wire       cmd_start, 
    input  wire [7:0] cmd_data, 
    output wire        cmd_done,  
    input wire is_last, // 【新增】 1:发送完发STOP, 0:发送完保持HOLD
    // --- IIC 接口 ---
    output reg       iic_scl,
    inout  wire      iic_sda
);

    localparam DIV_MAX = 125;
    
    localparam IDLE      = 0;
    localparam START     = 1; // 发送起始位
    localparam SEND_BYTE = 2; // 发送8位数据
    localparam READ_ACK  = 3; // 等待ACK
    localparam STOP      = 4; // 发送停止位
    localparam WAIT_NEXT = 5; // 等待下一个数据

    reg [2:0]  state;
    reg [7:0]  clk_cnt;
    wire       iic_tick;
    
    reg [2:0]  bit_cnt;
    reg [1:0]  quarter_cnt;             // 这是做什么的？

    reg sda_out;
    reg sda_link;                       // 方向1:out 2：in/Z


    // 数据锁存（调试时发现问题）
    reg       work_en;  // 记录是否收到了开始命令
    reg [7:0] tx_data;  // 锁存要发送的数据，防止外部数据变化


     // ===============================================
    // 1. 握手逻辑 (解决脉冲丢失的关键!)
    // ===============================================
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            work_en <= 0;
            tx_data <= 0;
        end
        else begin
            // 收到外部脉冲，立刻记录下来
            if(cmd_start) begin
                work_en <= 1'b1;
                tx_data <= cmd_data; // 顺便把数据也存好
            end
            // 如果状态机已经响应了(跳出了IDLE)，就可以把记录清除了
            else if(state == START) begin
                work_en <= 1'b0;
            end
        end
    end

    // iic时钟
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) begin clk_cnt <= 0;end
        else if(clk_cnt == DIV_MAX - 1) clk_cnt <= 0;
        else clk_cnt <= clk_cnt + 1;
    end

    assign iic_tick = (clk_cnt == DIV_MAX - 1);  // 每个iic时钟周期的最后一个clk周期拉高，脉冲

    // 状态机逻辑
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state <= IDLE;
            quarter_cnt <= 0;
            bit_cnt <= 0;
            sda_out <= 1;  // 默认高
            sda_link <= 1; // 初始拉高
        end 
        else if(iic_tick) begin // 【核心】所有的状态变化都只在 Tick 时刻发生
            if(state != IDLE) begin
                if(quarter_cnt == 3) 
                    quarter_cnt <= 0;
                else 
                    quarter_cnt <= quarter_cnt + 1;
                end
            case(state) 
                IDLE: begin
                    sda_out <= 1;  // 默认高
                    sda_link <= 1; // 默认拉高
                    quarter_cnt <= 0;
                    if(work_en) begin
                        state <= START;
                    end
                end

                START:begin // SCL高电平时，SDA拉低
                    if(quarter_cnt == 0) sda_out <= 1;      // SCL高电平，SDA拉高
                    else if(quarter_cnt == 2'd1) sda_out <= 0; // SCL高电平，SDA拉低(START)
                    else if(quarter_cnt == 2'd3) begin
                        state <= SEND_BYTE;
                        bit_cnt <= 0;
                        quarter_cnt <= 0;   // 重置
                    end
                end

                SEND_BYTE:begin
                    if(quarter_cnt == 2'd0)  begin// Q0: SCL低，SDA改变数据
                        sda_out <= tx_data[7 - bit_cnt]; end
                    if(quarter_cnt == 2'd3) begin
                        if(bit_cnt == 7) begin
                            state <= READ_ACK;
                            quarter_cnt <= 0;
                        end
                        else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end
                
                READ_ACK:begin
                    if(quarter_cnt == 2'd0) sda_link <= 0; // SDA设为输入
                    else if(quarter_cnt == 2'd2) begin // Q2: SCL高，SDA读取ACK
                        // reg ack_bit = iic_sda;
                    end else if(quarter_cnt == 2'd3) begin // Q3: ACK结束
                        if(is_last) begin state <= STOP; end
                        else begin 
                            state <= WAIT_NEXT; 
                        end
                        quarter_cnt <= 0;
                    end
                end
                WAIT_NEXT: begin
                    // 在这里 SCL 会保持低电平（因为不在 Q1/Q2）
                    // 我们等待上层再次给出 cmd_start (也就是 work_en)
                    if(work_en) begin
                        state    <= SEND_BYTE; // 直接去发数据，不要发 START！
                        bit_cnt  <= 0;
                        quarter_cnt <= 0;
                        // 注意：这里需要重新拿回 SDA 控制权
                        sda_link <= 1;
                        sda_out  <= 1; // 初始给个高，马上就会被 SEND_BYTE 覆盖
                    end
                end
                STOP: begin
                    if(quarter_cnt == 2'd0) begin
                        sda_link <= 1;
                        sda_out <= 0;
                    end else if(quarter_cnt == 2'd1) begin// Q1: SCL拉高，SDA保持0
                    end else if(quarter_cnt == 2'd2) begin
                        sda_out <= 1;
                    end else if(quarter_cnt == 2'd3) begin
                        state <= IDLE;
                    end                  
                end
            endcase
        end
    end



    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) iic_scl <= 1;
        else if(state == IDLE) iic_scl <= 1;
        else if(iic_tick) begin
            // --- Q3 结束时 (准备进 Q0) ---
            if (quarter_cnt == 3) begin
                if(state == STOP) iic_scl <= 1; // 【修正】STOP 结束进 IDLE，必须保持高
                else              iic_scl <= 0; // 其他状态(START/ACK/DATA)准备改数据，拉低
            end
            // --- Q0 结束时 (准备进 Q1) ---
            else if (quarter_cnt == 0) begin
                iic_scl <= 1; // 拉高，建立时钟
            end
            // --- Q2 结束时 (准备进 Q3) ---
            else if (quarter_cnt == 2) begin
                if(state == STOP) iic_scl <= 1; // 【修正】STOP 状态下，SCL 必须保持高，不能掉下去
                else              iic_scl <= 0; // 其他状态拉低，准备下一位
            end
        end
    end


    // SDA 输出
    assign iic_sda = sda_link ? sda_out : 1'bz;
    // 在 STOP 结束时 OR 在 WAIT_NEXT 刚进入时
    assign cmd_done = ((state == STOP) && (quarter_cnt == 2'd3) && iic_tick) || 
                      ((state == READ_ACK) && (quarter_cnt == 2'd3) && iic_tick && !is_last);




endmodule