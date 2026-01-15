module ram_rd(
    input              clk,
    input              rst_n,
    input              rd_start,    // 开始信号
    input      [7:0]   ram_rd_data, // 这里只是引进来为了观察，逻辑上不使用

    output             ram_rd_en,   // 输出给 IP 的 rden_b
    output reg [10:0]  ram_rd_addr
);

reg [5:0] rd_cnt;
reg       rd_active; // 激活标志

// 只有收到开始信号，且计数器在范围内，才拉高读使能
assign ram_rd_en = ((rd_cnt >= 1) && (rd_cnt <= 32) && rd_active) ? 1'b1 : 1'b0;

always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        rd_cnt    <= 0;
        rd_active <= 0;
    end else begin
        // 只有当写完信号到来，才激活
        if (rd_start) begin
            rd_active <= 1;
            
            if(rd_cnt < 7'd64)
                rd_cnt <= rd_cnt + 1'b1;
            else
                rd_cnt <= rd_cnt;
        end
    end
end

// 地址产生
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)
        ram_rd_addr <= 0;
    else if(ram_rd_en)
        ram_rd_addr <= ram_rd_addr + 1'b1;
    else
        ram_rd_addr <= 0;
end

endmodule