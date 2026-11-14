# Run from the MESI_Cache directory in ModelSim GUI: do run_g0_regression.do
# This script intentionally never exits the ModelSim application.
set run_id [clock format [clock seconds] -format %Y%m%d_%H%M%S]
set log_prefix "g0_tc8_${run_id}_"
while {[file exists "${log_prefix}compile.log"] || [file exists "${log_prefix}previous_g0_regression_summary.log"]} {
    append run_id "_1"
    set log_prefix "g0_tc8_${run_id}_"
}
set summary_log "g0_regression_summary.log"
set timestamp_summary "${log_prefix}regression_summary.log"
set compile_log "${log_prefix}compile.log"
set test_names {D1 D2 D3 D4 D5 SHARED_MEMORY BUS_ARBITER TB_TOP TC1 TC2 TC3 TC4 TC5 TC6 TC7 TC8 SCOREBOARD_NEGATIVE R1}
set test_logs [list \
    "${log_prefix}D1.log" "${log_prefix}D2.log" "${log_prefix}D3.log" \
    "${log_prefix}D4.log" "${log_prefix}D5.log" "${log_prefix}shared_memory.log" \
    "${log_prefix}bus_arbiter.log" "${log_prefix}tb_top.log" \
    "${log_prefix}tb_top.log" "${log_prefix}tb_top.log" "${log_prefix}tb_top.log" \
    "${log_prefix}tb_top.log" "${log_prefix}tb_top.log" "${log_prefix}tb_top.log" \
    "${log_prefix}TC7.log" "${log_prefix}TC8.log" \
    "${log_prefix}scoreboard_negative.log" "${log_prefix}R1.log"]

if {[file exists $summary_log]} {
    file copy $summary_log "${log_prefix}previous_g0_regression_summary.log"
}
proc summary_append {line} {
    global summary_log timestamp_summary
    foreach path [list $summary_log $timestamp_summary] {
        set sf [open $path a]
        puts $sf $line
        close $sf
    }
}
foreach path [list $summary_log $timestamp_summary] {
    set sf [open $path w]
    close $sf
}
summary_append "G0 regression started: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"

set compile_ok 1
transcript file $compile_log
if {[catch {
    if {![file exists g0_work]} { vlib g0_work }
    vmap g0_work g0_work
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/RegFile.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/mux2.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/instructionmemory.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/imm_Gen.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/flopr.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/Datapath.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/data_extract.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/Controller.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/ALUController.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/alu.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/adder.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/adder_32.sv
    vlog -sv -work g0_work ../RISC_V_Single_Clock_Non_Pipeline/RISC_V.sv
    vlog -work g0_work cache.v cache_controller.v bus_arbiter.v shared_memory.v top_multicore.v
    vlog -sv -work g0_work tb_d1.v tb_d2345.v tb_shared_memory.v tb_bus_arbiter.v tb_top.v tb_r1.v
    vlog -sv -work g0_work tb_top_tc78.v
} compile_error]} {
    set compile_ok 0
    summary_append "COMPILE: FAIL ($compile_error)"
    puts "\[G0 REGRESSION\] COMPILE FAIL: $compile_error"
} else {
    summary_append "COMPILE: PASS"
}

proc log_has {path needle} {
    if {![file exists $path]} { return 0 }
    set f [open $path r]
    set body [read $f]
    close $f
    return [expr {[string first $needle $body] >= 0}]
}

proc record_result {name result logfile} {
    summary_append "$name: $result (log: $logfile)"
    puts "\[G0 REGRESSION\] $name: $result (log: $logfile)"
}

proc run_positive {name top logfile marker sim_args} {
    set err ""
    transcript file $logfile
    if {[catch {eval [linsert $sim_args 0 vsim -onfinish stop -lib g0_work $top]} load_err]} {
        set err "load: $load_err"
    } elseif {[catch {run -all} run_err]} {
        set err "run: $run_err"
    }
    catch {transcript flush}
    catch {quit -sim}
    catch {transcript flush}

    if {$err eq "" && [log_has $logfile $marker] && ![log_has $logfile "FAIL"] && ![log_has $logfile "Fatal:"]} {
        record_result $name PASS $logfile
        return 1
    }
    if {$err ne ""} { puts "\[G0 REGRESSION\] $name simulator error: $err" }
    if {![log_has $logfile $marker]} { puts "\[G0 REGRESSION\] $name FAIL: missing PASS marker." }
    record_result $name FAIL $logfile
    return 0
}

proc run_expected_negative {name logfile} {
    set err ""
    transcript file $logfile
    if {[catch {vsim -onfinish stop -lib g0_work -gNEGATIVE_SCOREBOARD_TEST=1 tb_top} load_err]} {
        set err "load: $load_err"
    } elseif {[catch {run -all} run_err]} {
        # The checker is expected to terminate this deliberately perturbed run.
        set err $run_err
    }
    catch {transcript flush}
    catch {quit -sim}
    catch {transcript flush}

    if {[log_has $logfile {[NEGATIVE TEST] INJECTED:} ] &&
        [log_has $logfile {[GOLDEN CHECKER] FAIL:} ] &&
        [log_has $logfile "G0.5 golden checker did not pass"] &&
        ![log_has $logfile {[GOLDEN CHECKER] PASS:} ]} {
        record_result $name PASS_EXPECTED_FAIL $logfile
        return 1
    }
    if {$err ne ""} { puts "\[G0 REGRESSION\] $name simulator result: $err" }
    puts "\[G0 REGRESSION\] $name FAIL: checker did not produce the required negative evidence."
    record_result $name FAIL $logfile
    return 0
}

set passed_count 0
if {$compile_ok} {
    if {[run_positive D1 tb_d1 "${log_prefix}D1.log" {[D1] PASS:} {}]} { incr passed_count }
    if {[run_positive D2 tb_d2345 "${log_prefix}D2.log" {[D2] PASS:} {-gTEST_ID=2 -gCORE0_FILE=d2_core0.mem -gCORE1_FILE=d2_core1.mem}]} { incr passed_count }
    if {[run_positive D3 tb_d2345 "${log_prefix}D3.log" {[D3] PASS:} {-gTEST_ID=3 -gCORE0_FILE=d3_core0.mem -gCORE1_FILE=d3_core1.mem}]} { incr passed_count }
    if {[run_positive D4 tb_d2345 "${log_prefix}D4.log" {[D4] PASS:} {-gTEST_ID=4 -gCORE0_FILE=d4_core0.mem -gCORE1_FILE=d4_core1.mem}]} { incr passed_count }
    if {[run_positive D5 tb_d2345 "${log_prefix}D5.log" {[D5] PASS:} {-gTEST_ID=5 -gCORE0_FILE=d5_core0.mem -gCORE1_FILE=d5_core1.mem}]} { incr passed_count }
    if {[run_positive SHARED_MEMORY tb_shared_memory "${log_prefix}shared_memory.log" {[SHM] PASS:} {}]} { incr passed_count }
    if {[run_positive BUS_ARBITER tb_bus_arbiter "${log_prefix}bus_arbiter.log" {[BUS] PASS:} {}]} { incr passed_count }
    if {[run_positive TB_TOP tb_top "${log_prefix}tb_top.log" {[GOLDEN CHECKER] PASS:} {}]} { incr passed_count }
    foreach tc_id {1 2 3 4 5 6} {
        set tc_marker "\[TC${tc_id}\] PASS:"
        if {[log_has "${log_prefix}tb_top.log" $tc_marker] &&
            ![log_has "${log_prefix}tb_top.log" "\[TC${tc_id}\] FAIL"]} {
            record_result "TC${tc_id}" PASS "${log_prefix}tb_top.log"
            incr passed_count
        } else {
            record_result "TC${tc_id}" FAIL "${log_prefix}tb_top.log"
        }
    }
    if {[run_positive TC7 tb_top_tc78 "${log_prefix}TC7.log" {[TC7] PASS:} {-gTEST_ID=7}]} { incr passed_count }
    if {[run_positive TC8 tb_top_tc78 "${log_prefix}TC8.log" {[TC8] PASS:} {-gTEST_ID=8}]} { incr passed_count }
    if {[run_expected_negative SCOREBOARD_NEGATIVE "${log_prefix}scoreboard_negative.log"]} { incr passed_count }
    if {[run_positive R1 tb_r1 "${log_prefix}R1.log" {[R1] PASS:} {}]} { incr passed_count }
} else {
    foreach name $test_names logfile $test_logs {
        record_result $name "FAIL_NOT_RUN_COMPILE_ERROR" $logfile
    }
}

if {$compile_ok && $passed_count == 18} {
    summary_append "OVERALL PASS: all 18 outcomes ran; 17 positive tests/checks passed and the negative checker test observed the expected FAIL."
    puts "\[G0 REGRESSION\] OVERALL PASS: all 18 outcomes ran and met their expected outcomes."
} else {
    summary_append "OVERALL FAIL: $passed_count of 18 expected outcomes passed; inspect all individual logs."
    puts "\[G0 REGRESSION\] OVERALL FAIL: $passed_count of 18 expected outcomes passed; see $summary_log"
}
# Intentionally no quit/exit: keep the ModelSim GUI open.
