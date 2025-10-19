module key_filter (
    input wire clk,
    input wire rst_n,
    input wire key,
    // output reg key_p_flag,
    // output reg key_r_flag,
    output key_flag,
    output reg key_state
);

    reg key_p_flag;
    reg key_r_flag;
    assign key_flag = key_p_flag | key_r_flag;

    // 前后电平状态存储
    reg [2:0] r_key_sync;
    always @(posedge clk)
        r_key_sync <= {r_key_sync[1:0], key};


    wire pedge_key;
    wire nedge_key;
    assign pedge_key = r_key_sync[2:1]==2'b01;
    assign nedge_key = r_key_sync[2:1]==2'b10;


    reg [19:0] cnt; // 20位计数器
    parameter CNT_20ms = 20'd1_000_000; // 20ms@50MHz

    reg [1:0] state;
    parameter IDLE = 2'b00; // 空闲
    parameter P_FILTER = 2'b01; // 
    parameter WAIT_R = 2'b10; // 
    parameter R_FILTER = 2'b11; // 持续释放状态

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            state <= IDLE;
            key_p_flag <= 0;
            key_r_flag <= 0;
            cnt <= 0;
            key_state <= 1;
			end
        else begin
            case(state)
                IDLE:begin
                    key_r_flag <= 0;        
                    if(nedge_key)
					begin
                        state <= P_FILTER;
                        cnt <= 0;
                    end else
                    state <= IDLE;
                end
                P_FILTER:begin
                    if(pedge_key && cnt < CNT_20ms-1)
                        state <= IDLE;
                    else if(cnt >= CNT_20ms-1)begin
                        state <= WAIT_R;
                        key_p_flag <= 1; // 触发
                        key_state <= 0;
                    end
                    else begin
                        state <= P_FILTER;
                        cnt <= cnt + 1'b1;
                    end
                end
                WAIT_R:begin
                    key_p_flag <= 0;      // 只保持一个clk周期
                    if(pedge_key)begin
                        state <= R_FILTER;
                        cnt <= 0;
					end								
                  else
                    state <= WAIT_R;
                end
                R_FILTER:begin
                    if(nedge_key && cnt < CNT_20ms-1)
                        state <= WAIT_R;
                    else if(cnt >= CNT_20ms-1)begin
                        state <= IDLE;
                        key_r_flag <= 1; // 触发
                        key_state <= 1;
                    end
                    else begin
                        state <= R_FILTER;
                        cnt <= cnt + 1'b1;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end




endmodule
