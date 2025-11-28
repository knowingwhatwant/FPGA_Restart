`timescale 1ns/1ns
module ip_2port_ram_tb();

reg        clk;
reg        rst_n;

always #10 clk = ~clk; //@50MHz


initial begin
    clk = 0;
    rst_n = 0;
    #201 rst_n = 1;
    #2000 $stop;    
end

    ip_2port_ram u_ip_2port_ram(
    .clk(clk),
    .rst_n(rst_n)
);



endmodule