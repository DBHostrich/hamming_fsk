library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

-- Same 18 clock/reset/LED pins as the baseline. No ADC/DAC pins added yet.
entity hamming_fsk_stream_board is
    generic (INTERLEAVE_DEPTH : positive := 8;
             ERROR_MODE : natural range 0 to 3 := 2;
             BURST_LENGTH : natural range 0 to BODY_BITS := 4;
             RANDOM_THRESHOLD : natural range 0 to 65535 := 0);
    port (sys_clk,reset : in std_logic;
          led_1,led_2 : out std_logic_vector(0 to 7));
end;
architecture rtl of hamming_fsk_stream_board is
    signal reset_meta,reset_sync : std_logic := '1';
    signal tx_count,rx_count,crc_count,missing_count,raw_errors,raw_bits,
           payload_errors,payload_bits,syndromes,acquisitions,latency : count_t;
    signal done,crc_good,locked : std_logic;
    signal seq : unsigned(15 downto 0);
    signal phase : unsigned(7 downto 0);
    signal payload : payload_t;
begin
    process(sys_clk)
    begin
        if rising_edge(sys_clk) then reset_meta<=not reset; reset_sync<=reset_meta; end if;
    end process;
    link : entity work.hamming_fsk_stream(rtl)
        generic map(INTERLEAVE_DEPTH=>INTERLEAVE_DEPTH,SAMPLE_DIV=>32,SAMPLES_PER_SYMBOL=>128)
        port map(clk=>sys_clk,reset=>reset_sync,rx_enable=>'1',external_rx=>'0',
                 rx_sample_in=>to_signed(0,8),error_mode=>to_unsigned(ERROR_MODE,2),
                 random_threshold=>to_unsigned(RANDOM_THRESHOLD,16),burst_start=>70,
                 burst_length=>BURST_LENGTH,sample_ce_out=>open,tx_sample_out=>open,
                 rx_frame_done=>done,rx_crc_ok=>crc_good,rx_locked=>locked,
                 rx_sequence=>seq,rx_payload=>payload,rx_timing_phase=>phase,
                 frames_tx=>tx_count,frames_rx=>rx_count,crc_error_frames=>crc_count,
                 missing_frames=>missing_count,raw_bit_errors=>raw_errors,raw_bits_checked=>raw_bits,
                 payload_bit_errors=>payload_errors,payload_bits_checked=>payload_bits,
                 syndrome_word_count=>syndromes,sync_acquisitions=>acquisitions,latency_cycles=>latency);
    -- Read by the existing QSF signal order, not by physical left-to-right order.
    led_1(0)<=locked;
    led_1(1)<='1' when rx_count/=0 else '0';
    led_1(2)<='1' when crc_count/=0 else '0';
    led_1(3)<='1' when raw_errors/=0 else '0';
    led_1(4)<='1' when payload_errors/=0 else '0';
    led_1(5)<='1' when syndromes/=0 else '0';
    led_1(6)<=rx_count(4);
    led_1(7)<=tx_count(4);
    led_2<=std_logic_vector(seq(7 downto 0));
end;
