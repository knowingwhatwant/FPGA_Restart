module ram_wr(
    input             clk,
    input             rst_n,

    output            ram_wr_en,
    output reg [10:0] ram_wr_addr,
    output reg [7:0]  ram_wr_data,
    output reg        wr_done
);

reg [10:0] wr_cnt;

// 产生写使能：计数器在 1~32 范围内时有效
assign ram_wr_en = ((wr_cnt >= 1) && (wr_cnt <= 32) && rst_n) ? 1'b1 : 1'b0;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        wr_cnt  <= 0;
        wr_done <= 0;
    end else begin
        // 计数器逻辑
        if(wr_cnt < 11'd60) begin
            wr_cnt <= wr_cnt + 1;
        end else begin
            wr_cnt <= wr_cnt; // 停止计数
        end
        
        // 状态指示：写完35个周期后，认为写入彻底完成
        if (wr_cnt > 35) 
            wr_done <= 1;
        else
            wr_done <= 0;
    end
end

// 数据产生：数据 = 当前数据 + 1
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) 
        ram_wr_data <= 1;
    else if(ram_wr_en) 
        ram_wr_data <= ram_wr_data + 1'b1;
    else
        ram_wr_data <= 8'd1;
end

// 地址产生：地址递增
always@(posedge clk or negedge rst_n) begin
    if(!rst_n) 
        ram_wr_addr <= 0;
    else if(ram_wr_en)
        ram_wr_addr <= ram_wr_addr + 1'b1;
    else
        ram_wr_addr <= 0;
end

endmodule