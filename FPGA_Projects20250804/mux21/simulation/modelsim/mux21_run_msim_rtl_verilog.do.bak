transcript on
if {[file exists rtl_work]} {
	vdel -lib rtl_work -all
}
vlib rtl_work
vmap work rtl_work

vlog -vlog01compat -work work +incdir+F:/FPGA/FPGA_Projects20250804/mux21 {F:/FPGA/FPGA_Projects20250804/mux21/mux21.v}

vlog -vlog01compat -work work +incdir+F:/FPGA/FPGA_Projects20250804/mux21/simulation/modelsim {F:/FPGA/FPGA_Projects20250804/mux21/simulation/modelsim/mux21.vt}

vsim -t 1ps -L altera_ver -L lpm_ver -L sgate_ver -L altera_mf_ver -L altera_lnsim_ver -L cycloneive_ver -L rtl_work -L work -voptargs="+acc"  mux21_tb

add wave *
view structure
view signals
run -all
