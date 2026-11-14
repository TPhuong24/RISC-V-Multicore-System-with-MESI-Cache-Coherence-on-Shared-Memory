# Run with: do run_d1_d5.do, from the MESI_Cache directory in the ModelSim GUI.
# Never quit the ModelSim application. "quit -sim" only closes a simulation.
set summary_log "d1_d5_summary.log"
set test_logs {d1_d5_D1.log d1_d5_D2.log d1_d5_D3.log d1_d5_D4.log d1_d5_D5.log}
set sf [open $summary_log w]
puts $sf "D1-D5 regression started"
close $sf
foreach logfile $test_logs {
    set lf [open $logfile w]
    puts $lf ""
    close $lf
}

set compile_ok 1
if {[catch {
    if {![file exists d1_d5_work]} { vlib d1_d5_work }
    vmap d1_d5_work d1_d5_work
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/RegFile.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/mux2.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/instructionmemory.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/imm_Gen.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/flopr.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/Datapath.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/data_extract.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/Controller.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/ALUController.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/alu.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/adder.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/adder_32.sv
    vlog -sv -work d1_d5_work ../RISC_V_Single_Clock_Non_Pipeline/RISC_V.sv
    vlog -work d1_d5_work cache.v cache_controller.v bus_arbiter.v shared_memory.v top_multicore.v
    vlog -sv -work d1_d5_work tb_d1.v tb_d2345.v
} compile_error]} {
    set compile_ok 0
    set sf [open $summary_log a]
    puts $sf "FAIL: compile/setup error: $compile_error"
    close $sf
    puts "\[REGRESSION\] FAIL: compile/setup error; see $summary_log"
}

proc run_test {id top logfile sim_args} {
    global summary_log
    transcript file $logfile
    set passed 0
    set err ""
    if {[catch {eval [linsert $sim_args 0 vsim -onfinish stop -lib d1_d5_work $top]} load_result]} {
        set err $load_result
        puts "\[D${id}\] FAIL: could not load test: $err"
    } elseif {[catch {run -all} run_result]} {
        set err $run_result
        puts "\[D${id}\] FAIL: simulation command failed or was interrupted: $err"
    }
    catch {transcript flush}
    catch {quit -sim}
    catch {transcript flush}

    set f [open $logfile r]
    set log_text [read $f]
    close $f
    if {$err eq "" && [string first "\[D${id}\] PASS:" $log_text] >= 0} {
        set passed 1
        set result "PASS"
    } else {
        set result "FAIL"
        if {$err ne ""} { puts "\[REGRESSION\] D${id} error: $err" }
        if {[string first "\[D${id}\] FAIL" $log_text] < 0} {
            puts "\[D${id}\] FAIL: no PASS marker found; test may have stopped early."
        }
    }
    set sf [open $summary_log a]
    puts $sf "D${id}: $result (log: $logfile)"
    close $sf
    puts "\[REGRESSION\] D${id}: $result (log: $logfile)"
    return $passed
}

set pass_count 0
if {$compile_ok} {
    if {[run_test 1 tb_d1 d1_d5_D1.log {}]} { incr pass_count }
    if {[run_test 2 tb_d2345 d1_d5_D2.log {-gTEST_ID=2 -gCORE0_FILE=d2_core0.mem -gCORE1_FILE=d2_core1.mem}]} { incr pass_count }
    if {[run_test 3 tb_d2345 d1_d5_D3.log {-gTEST_ID=3 -gCORE0_FILE=d3_core0.mem -gCORE1_FILE=d3_core1.mem}]} { incr pass_count }
    if {[run_test 4 tb_d2345 d1_d5_D4.log {-gTEST_ID=4 -gCORE0_FILE=d4_core0.mem -gCORE1_FILE=d4_core1.mem}]} { incr pass_count }
    if {[run_test 5 tb_d2345 d1_d5_D5.log {-gTEST_ID=5 -gCORE0_FILE=d5_core0.mem -gCORE1_FILE=d5_core1.mem}]} { incr pass_count }
} else {
    foreach id {1 2 3 4 5} logfile $test_logs {
        set sf [open $summary_log a]
        puts $sf "D${id}: FAIL (NOT RUN because compile/setup failed; log: $logfile)"
        close $sf
    }
}

set sf [open $summary_log a]
if {$compile_ok && $pass_count == 5} {
    puts $sf "OVERALL PASS: all five tests ran and passed."
    puts "\[REGRESSION\] OVERALL PASS: D1-D5 all ran and passed."
} else {
    puts $sf "OVERALL FAIL: $pass_count of 5 tests passed; see individual logs."
    puts "\[REGRESSION\] OVERALL FAIL: $pass_count of 5 tests passed; see $summary_log"
}
close $sf

# Deliberately leave ModelSim GUI open for inspecting the last test/logs.
