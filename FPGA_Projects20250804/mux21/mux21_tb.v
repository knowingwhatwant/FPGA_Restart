`timescale 1ns /1ns



module mux21_tb();

	reg s_a;
	reg s_b;
	reg sel;
	wire out;


	mux21 mux21_inst0(
	.a(s_a),
	.b(s_b),
	.sel(sel),
	.out(out)
	);
	
	
	initial begin
		s_a=0;s_b=0;sel=0;
		#200;
		s_a=0;s_b=0;sel=1;
		#200;
		s_a=0;s_b=1;sel=0;
		#200;
		s_a=0;s_b=1;sel=1;
		#200;
		s_a=1;s_b=0;sel=0;
		#200;
		s_a=1;s_b=0;sel=1;
		#200;
		s_a=1;s_b=1;sel=0;
		#200;
		s_a=1;s_b=1;sel=1;
		#200;
		
		
	
	end






endmodule