transcript on
if {[file exists gate_work]} {
	vdel -lib gate_work -all
}
vlib gate_work
vmap work gate_work

vlog -vlog01compat -work work +incdir+. {decode3_8_7_1200mv_85c_slow.vo}

vlog -vlog01compat -work work +incdir+F:/FPGA_Restart/FPGA_Projects20250804/decode3_8 {F:/FPGA_Restart/FPGA_Projects20250804/decode3_8/decode3_8_tb.v}

vsim -t 1ps +transport_int_delays +transport_path_delays -L altera_ver -L cycloneive_ver -L gate_work -L work -voptargs="+acc"  decode3_8_tb

add wave *
view structure
view signals
run -all
