# Run from the MESI_Cache directory in the ModelSim GUI: do run_u1.do
# Compiles an isolated core testbench and runs six independently logged ROM tests.
# This script never exits the ModelSim application.

set summary_log "u1_summary.log"
set compile_log "u1_compile.log"
set test_names {ALU BRANCH JAL JALR PC32 MEM}
set test_logs {u1_alu.log u1_branch.log u1_jal.log u1_jalr.log u1_pc32.log u1_mem.log}

set sf [open $summary_log w]
puts $sf "U1 directed core tests started"
close $sf

set compile_ok 1
set compile_error ""
transcript file $compile_log
if {[catch {
    if {![file exists u1_work]} { vlib u1_work }
    vmap u1_work u1_work
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/RegFile.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/mux2.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/instructionmemory.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/imm_Gen.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/Datapath.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/data_extract.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/Controller.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/ALUController.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/alu.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/adder.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/adder_32.sv
    vlog -sv -work u1_work ../RISC_V_Single_Clock_Non_Pipeline/RISC_V.sv
    vlog -sv -work u1_work tb_u1.v
} compile_error]} {
    set compile_ok 0
    set sf [open $summary_log a]
    puts $sf "COMPILE: FAIL ($compile_error)"
    close $sf
    puts "\[U1\] COMPILE FAIL: $compile_error"
} else {
    set sf [open $summary_log a]
    puts $sf "COMPILE: PASS"
    close $sf
    puts "\[U1\] COMPILE PASS"
}

proc u1_log_has {path needle} {
    if {![file exists $path]} { return 0 }
    set f [open $path r]
    set body [read $f]
    close $f
    return [expr {[string first $needle $body] >= 0}]
}

proc u1_record {name result logfile} {
    global summary_log
    set sf [open $summary_log a]
    puts $sf "$name: $result (log: $logfile)"
    close $sf
    puts "\[U1\] $name: $result (log: $logfile)"
}

proc u1_run {name test_id image marker logfile} {
    set err ""
    transcript file $logfile
    if {[catch {vsim -onfinish stop -lib u1_work -gTEST_ID=$test_id -gPROGRAM_FILE=$image tb_u1} load_err]} {
        set err "load: $load_err"
    } elseif {[catch {run -all} run_err]} {
        set err "run: $run_err"
    }
    catch {transcript flush}
    catch {quit -sim}
    catch {transcript flush}

    if {$err eq "" && [u1_log_has $logfile $marker] &&
        ![u1_log_has $logfile "FAIL"] && ![u1_log_has $logfile "Fatal:"]} {
        u1_record $name PASS $logfile
        return 1
    }
    if {$err ne ""} { puts "\[U1\] $name simulator error: $err" }
    u1_record $name FAIL $logfile
    return 0
}

set passed_count 0
if {$compile_ok} {
    if {[u1_run ALU 1 u1_alu.mem {[U1][ALU] PASS} u1_alu.log]} { incr passed_count }
    if {[u1_run BRANCH 2 u1_branch.mem {[U1][BRANCH] PASS} u1_branch.log]} { incr passed_count }
    if {[u1_run JAL 3 u1_jal.mem {[U1][JAL] PASS} u1_jal.log]} { incr passed_count }
    if {[u1_run JALR 4 u1_jalr.mem {[U1][JALR] PASS} u1_jalr.log]} { incr passed_count }
    if {[u1_run PC32 5 u1_pc32.mem {[U1][PC32] PASS} u1_pc32.log]} { incr passed_count }
    if {[u1_run MEM 6 u1_mem.mem {[U1][MEM] PASS} u1_mem.log]} { incr passed_count }
} else {
    foreach name $test_names logfile $test_logs {
        u1_record $name FAIL_NOT_RUN_COMPILE_ERROR $logfile
    }
}

set sf [open $summary_log a]
if {$compile_ok && $passed_count == 6} {
    puts $sf "OVERALL PASS: all six U1 tests ran and passed."
    puts "\[U1\] OVERALL PASS: all six U1 tests ran and passed."
} else {
    puts $sf "OVERALL FAIL: $passed_count of 6 tests passed; inspect individual logs."
    puts "\[U1\] OVERALL FAIL: $passed_count of 6 tests passed; see $summary_log"
}
close $sf

# Intentionally no quit/exit: keep the ModelSim GUI open.
