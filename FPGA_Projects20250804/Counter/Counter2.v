module Counter2(
    input clk,
    input rst_n,
	 output reg led
);

	reg [24:0] counter;


// 纯时序逻辑实现计数器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter <= 0;  
    end else if(counter == 25000000-1) begin
         counter <= 0;
    end else begin
         counter <= counter + 1'b1; 
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        led <= 0;  
    end else if(count == 25000000-1) begin
         led <= ~led;
    end
end

endmodule