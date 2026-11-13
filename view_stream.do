do compile_stream.do
vsim -t 1ns -gDEPTH=8 work.tb_comm_stream
set BreakOnAssertion 2
add wave -divider {Control and sampled waveform}
add wave sim:/tb_comm_stream/clk sim:/tb_comm_stream/reset sim:/tb_comm_stream/rx_enable
add wave -radix decimal sim:/tb_comm_stream/tx_sample
add wave sim:/tb_comm_stream/locked
add wave -radix unsigned sim:/tb_comm_stream/phase
add wave -divider {Recovered frames}
add wave sim:/tb_comm_stream/frame_done sim:/tb_comm_stream/crc_good
add wave -radix unsigned sim:/tb_comm_stream/seq
add wave -radix hexadecimal sim:/tb_comm_stream/payload
add wave -divider {Fault controls and cumulative counters}
add wave -radix unsigned sim:/tb_comm_stream/mode sim:/tb_comm_stream/burst_length
add wave -radix unsigned sim:/tb_comm_stream/tx_count sim:/tb_comm_stream/rx_count
add wave -radix unsigned sim:/tb_comm_stream/raw_errors sim:/tb_comm_stream/payload_errors
add wave -radix unsigned sim:/tb_comm_stream/crc_count sim:/tb_comm_stream/missing_count
run -all
wave zoom full
