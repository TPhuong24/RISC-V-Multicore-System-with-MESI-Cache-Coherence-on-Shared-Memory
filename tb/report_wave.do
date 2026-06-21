onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {=== SYSTEM ===}
add wave -noupdate /tb_top/clk
add wave -noupdate /tb_top/rst_n
add wave -noupdate /tb_top/tc_counter
add wave -noupdate -divider {=== BUS ARBITER ===}
add wave -noupdate /tb_top/dut/bus_arb/c0_bus_req
add wave -noupdate /tb_top/dut/bus_arb/c1_bus_req
add wave -noupdate /tb_top/dut/bus_arb/last_grant
add wave -noupdate /tb_top/dut/bus_arb/c0_bus_grant
add wave -noupdate /tb_top/dut/bus_arb/c1_bus_grant
add wave -noupdate /tb_top/dut/bus_arb/mem_ready
add wave -noupdate /tb_top/prev_mem_wen
add wave -noupdate -divider {=== CORE 0 ===}
add wave -noupdate -color Magenta /tb_top/c0_state
add wave -noupdate -color Magenta /tb_top/c0_actual_mesi
add wave -noupdate -color Magenta -radix hexadecimal /tb_top/c0_instr
add wave -noupdate -color Magenta -radix hexadecimal /tb_top/c0_pc
add wave -noupdate -color Magenta -radix hexadecimal /tb_top/c0_cache_data
add wave -noupdate -radix hexadecimal /tb_top/c0_mem_instr
add wave -noupdate -radix hexadecimal /tb_top/c0_mem_pc
add wave -noupdate -radix hexadecimal /tb_top/out_core0_wb_data
add wave -noupdate -divider {=== CORE 1 ===}
add wave -noupdate -color Gold /tb_top/c1_state
add wave -noupdate -color Gold /tb_top/c1_actual_mesi
add wave -noupdate -color Gold -radix hexadecimal /tb_top/c1_instr
add wave -noupdate -color Gold -radix hexadecimal /tb_top/c1_pc
add wave -noupdate -color Gold -radix hexadecimal /tb_top/c1_cache_data
add wave -noupdate -radix hexadecimal /tb_top/c1_mem_instr
add wave -noupdate -radix hexadecimal /tb_top/c1_mem_pc
add wave -noupdate -radix hexadecimal /tb_top/out_core1_wb_data
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {636867 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 214
configure wave -valuecolwidth 40
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {1496940 ps}
