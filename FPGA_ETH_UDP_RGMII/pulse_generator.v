module pulse_generator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_trig,   // 启动触发
    input  wire [15:0] pulse_num_in, // [新增] 这次要发多少个？
    output reg         pulse_out,
    output reg         busy
);

    // 固定参数：频率控制 (30kHz)
    localparam CNT_MAX   = 1667; // 50MHz / 30kHz
    localparam CNT_HALF  = 833;

    reg [11:0] freq_cnt;
    reg [15:0] pulse_cnt;      // 计数器改为 16位，以防数量很大
    reg [15:0] target_num_reg; // [新增] 内部寄存器，用于锁存目标数量
    reg        is_running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_out      <= 0;
            busy           <= 0;
            freq_cnt       <= 0;
            pulse_cnt      <= 0;
            is_running     <= 0;
            target_num_reg <= 0;
        end else begin
            // 1. 启动逻辑
            if (start_trig && !is_running) begin
                is_running     <= 1;
                busy           <= 1;
                freq_cnt       <= 0;
                pulse_cnt      <= 0;
                pulse_out      <= 1;
                // [关键] 锁存外部传入的目标数量
                // 如果传入0，默认发200，防止出错
                if (pulse_num_in == 0) target_num_reg <= 200;
                else                   target_num_reg <= pulse_num_in;
            end
            
            // 2. 运行逻辑
            else if (is_running) begin
                // 频率周期计数
                if (freq_cnt < CNT_MAX - 1) begin
                    freq_cnt <= freq_cnt + 1'b1;
                end else begin
                    freq_cnt <= 0;
                    
                    // 脉冲个数计数：对比 target_num_reg
                    if (pulse_cnt < target_num_reg - 1) begin
                        pulse_cnt <= pulse_cnt + 1'b1;
                    end else begin
                        // 完成任务
                        is_running <= 0;
                        busy       <= 0;
                        pulse_out  <= 0;
                    end
                end

                // 波形翻转
                if (freq_cnt < CNT_HALF) pulse_out <= 1;
                else                     pulse_out <= 0;
            end
            // 空闲逻辑
            else begin
                pulse_out <= 0;
                busy      <= 0;
            end
        end
    end

endmodule