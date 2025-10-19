module smg_disp(
input clk,
input rst_n,
output reg [7:0] smg_sel,
output reg [7:0] smg_out
);

    reg [15:0] clk_div;
    reg [2:0] scan_cnt;
    reg clk_10k;
    parameter CLK_10K = 16'd24999;
    wire [31:0] data_in;
    assign data_in = 32'h0123_4567;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            clk_div <= 16'd0;
        else if(clk_div >= CLK_10K)begin
            clk_div <= 16'd0;
            clk_10k <= ~clk_10k;
		 end
        else
            clk_div <= clk_div + 1'b1;
    end

    always @(posedge clk_10k or negedge rst_n) begin 
        if(!rst_n)
            scan_cnt <= 3'd0;
        else if(scan_cnt >= 3'd7)
            scan_cnt <= 3'd0;
        else
            scan_cnt <= scan_cnt + 1'b1;
    end

    always@(*) begin
        case (scan_cnt)
            3'b000: smg_sel = 8'b0000_0001;
            3'b001: smg_sel = 8'b0000_0010;
            3'b010: smg_sel = 8'b0000_0100;
            3'b011: smg_sel = 8'b0000_1000;
            3'b100: smg_sel = 8'b0001_0000;
            3'b101: smg_sel = 8'b0010_0000;
            3'b110: smg_sel = 8'b0100_0000;
            3'b111: smg_sel = 8'b1000_0000;
            default: smg_sel = 8'b0000_0000;
        endcase
    end
    reg [7:0] smg_out_temp;
    always@(*) begin
        case (scan_cnt)
            3'b000: smg_out_temp = data_in[31:24];
            3'b001: smg_out_temp = data_in[23:16];
            3'b010: smg_out_temp = data_in[15:8];
            3'b011: smg_out_temp = data_in[7:0];
            3'b100: smg_out_temp = data_in[31:24];
            3'b101: smg_out_temp = data_in[23:16];
            3'b110: smg_out_temp = data_in[15:8];
            3'b111: smg_out_temp = data_in[7:0];
            default: smg_out = 8'b0000_0000;
        endcase
    end

    // 共阳显示
    always@(*) begin
        case (smg_out_temp)
            8'h00: smg_out = 8'hc0; //0
            8'h01: smg_out = 8'hf9; //1
            8'h02: smg_out = 8'ha4; //2
            8'h03: smg_out = 8'hb0; //3
            8'h04: smg_out = 8'h99; //4
            8'h05: smg_out = 8'h92; //5
            8'h06: smg_out = 8'h82; //6
            8'h07: smg_out = 8'hf8; //7
            8'h08: smg_out = 8'h80; //8
            8'h09: smg_out = 8'h90; //9
            8'h0A: smg_out = 8'h88; //A
            8'h0B: smg_out = 8'h83; //B
            8'h0C: smg_out = 8'hc6; //C
            8'h0D: smg_out = 8'ha1; //D
            8'h0E: smg_out = 8'h86; //E
            8'h0F: smg_out = 8'h8e; //F
            default: smg_out = 8'b1111_1111; //off
        endcase
    end



endmodule