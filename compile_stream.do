# Run from this project directory. Works with VHDL-93 ModelSim projects.
onerror {quit -code 1}
if {![file exists sim_work]} {vlib sim_work}
vmap work sim_work
vcom -93 comm_stream_pkg.vhd
vcom -93 comm_packet_tx.vhd
vcom -93 comm_sample_rx.vhd
vcom -93 comm_bit_channel.vhd
vcom -93 comm_packet_rx.vhd
vcom -93 hamming_fsk_stream.vhd
vcom -93 hamming_fsk_stream_board.vhd
vcom -93 tb_comm_codec.vhd
vcom -93 tb_comm_stream.vhd
vcom -93 tb_comm_sync.vhd
