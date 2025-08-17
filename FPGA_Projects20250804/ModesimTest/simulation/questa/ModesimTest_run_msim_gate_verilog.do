transcript on
if {[file exists gate_work]} {
	vdel -lib gate_work -all
}
vlib gate_work
vmap work gate_work

vlog -vlog01compat -work work +incdir+. {ModesimTest.vo}

vlog -vlog01compat -work work +incdir+F:/FPGA_Restart/FPGA_Projects20250804/ModesimTest {F:/FPGA_Restart/FPGA_Projects20250804/ModesimTest/simple_top_tb.v}

vsim -t 1ps -L altera_ver -L cycloneive_ver -L gate_work -L work -voptargs="+acc"  simple_top_tb

add wave *
view structure
view signals
run -all
