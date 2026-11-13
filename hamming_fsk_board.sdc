# The V2 course board uses a 60.8 MHz oscillator (period in ns).
create_clock -name sys_clk -period 16.447 [get_ports {sys_clk}]
derive_clock_uncertainty

# Only the asynchronous button input to the first synchronizer is excepted.
set_false_path -from [get_ports {reset}] -to [get_registers {reset_meta}]
