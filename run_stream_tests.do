# User-run regression. Intentionally does not download/program hardware.
do compile_stream.do
onbreak {abort}
vsim -t 1ns work.tb_comm_codec
set BreakOnAssertion 2
run -all
quit -sim
foreach depth {1 4 8} {
    vsim -t 1ns -gDEPTH=$depth work.tb_comm_stream
    set BreakOnAssertion 2
    run -all
    quit -sim
}
vsim -t 1ns -gPHASE_CASES=128 work.tb_comm_sync
set BreakOnAssertion 2
run -all
# Leave the final simulation open for inspection.
