// ============================================================================
// Module: ip_checksum_calculator
// Description: 通用的 IPv4 首部校验和计算器。
// 算法：16位反码求和（Ones' Complement Sum），两次回卷。
// ============================================================================

module ip_checksum_calculator (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          
    input  wire [15:0] word0, word1, word2, word3, word4, 
    input  wire [15:0] word5, word6, word7, word8, word9,
    output reg  [15:0] checksum_out,   
    output reg         done            
);

    reg [31:0] sum;
    reg [2:0]  state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 0; done <= 0;
        end else begin
            case (state)
                0: if (start) begin 
                    sum <= 0; done <= 0; state <= 1; 
                end
                1: begin
                    sum <= word0 + word1 + word2 + word3 + word4 + 
                           word5 + word6 + word7 + word8 + word9;
                    state <= 2;
                end
                2: begin // 第一次回卷
                    sum <= sum[31:16] + sum[15:0];
                    state <= 3;
                end
                3: begin // 第二次回卷
                    sum <= sum[31:16] + sum[15:0];
                    state <= 4;
                end
                4: begin
                    checksum_out <= ~sum[15:0];
                    done <= 1;
                    state <= 0;
                end
            endcase
        end
    end
endmodule