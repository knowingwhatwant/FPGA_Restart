module counter_led(
    input clk,
    input rst_n,
    input [31:0] time_set,
    input [7:0] ctrl,
    output reg led_out
);

    reg [2:0] counter;
    reg [31:0] cnt;
    
    // 记时间
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
             cnt <= 0;
        end
        else if(cnt == time_set - 1)     
            cnt <= 0;
        else
            cnt <= cnt + 1'b1;
    end

    // 记状态
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
             counter <= 0;
        end
        else if(cnt == time_set - 1)     
            counter <= counter + 1'b1;
        else
            counter <= 0;
    end
        
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
             led_out <= 0;
        end
        else case(counter)
            3'b000: led_out <= ctrl[0];
            3'b001: led_out <= ctrl[1];
            3'b010: led_out <= ctrl[2];
            3'b011: led_out <= ctrl[3];
            3'b100: led_out <= ctrl[4];
            3'b101: led_out <= ctrl[5];
            3'b110: led_out <= ctrl[6];
            3'b111: led_out <= ctrl[7];
            default: led_out <= 0;
            endcase
    end

endmodule