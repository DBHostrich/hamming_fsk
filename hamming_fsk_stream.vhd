library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

-- Continuous sampled link. SAMPLE_DIV=32 gives 1.9 MSPS at 60.8 MHz.
-- external_rx=0 selects internal sampled loopback; external_rx=1 selects
-- rx_sample_in (signed/centered samples, same sample_ce cadence).
entity hamming_fsk_stream is
    generic (INTERLEAVE_DEPTH : positive := 8; SAMPLE_DIV : positive := 32;
             SAMPLES_PER_SYMBOL : positive := 128);
    port (clk,reset,rx_enable : in std_logic;
          external_rx : in std_logic;
          rx_sample_in : in sample_t;
          error_mode : in unsigned(1 downto 0);
          random_threshold : in unsigned(15 downto 0);
          burst_start : in natural range 0 to BODY_BITS-1;
          burst_length : in natural range 0 to BODY_BITS;
          sample_ce_out : out std_logic;
          tx_sample_out : out sample_t;
          rx_frame_done,rx_crc_ok,rx_locked : out std_logic;
          rx_sequence : out unsigned(15 downto 0);
          rx_payload : out payload_t;
          rx_timing_phase : out unsigned(7 downto 0);
          frames_tx,frames_rx,crc_error_frames,missing_frames : out count_t;
          raw_bit_errors,raw_bits_checked,payload_bit_errors,payload_bits_checked : out count_t;
          syndrome_word_count,sync_acquisitions,latency_cycles : out count_t);
end;

architecture rtl of hamming_fsk_stream is
    signal divider : natural range 0 to SAMPLE_DIV-1 := 0;
    signal sample_ce,rx_reset : std_logic;
    signal tx_sample,rx_sample : sample_t;
    signal tx_start,body_start,demod_valid,demod_bit : std_logic;
    signal channel_valid,channel_bit,injected : std_logic;
    signal frame_done,crc_good : std_logic;
    signal tx_seq,decoded_seq : unsigned(15 downto 0);
    signal tx_payload,decoded_payload : payload_t;
    signal tx_body : body_t;
    signal frame_syndromes : unsigned(5 downto 0);
    -- Diagnostic references are captured here, outside both receiver entities.
    -- They never determine timing, sync, Hamming correction or CRC acceptance.
    signal expected_payload : payload_t := (others=>'0');
    signal expected_body : body_t := (others=>'0');
    signal reference_index : natural range 0 to BODY_BITS-1 := 0;
    signal tx_count,rx_count,crc_count,missing_count : count_t := (others=>'0');
    signal raw_errors,raw_bits,payload_errors,payload_bits : count_t := (others=>'0');
    signal syndrome_count,sync_count : count_t := (others=>'0');
    signal clock_count,tx_start_cycle,frame_start_cycle,last_latency : count_t := (others=>'0');
    signal last_good_seq : unsigned(15 downto 0) := (others=>'0');
    signal have_good_seq : std_logic := '0';
begin
    sample_ce<='1' when divider=SAMPLE_DIV-1 else '0';
    sample_ce_out<=sample_ce; tx_sample_out<=tx_sample;
    rx_sample<=rx_sample_in when external_rx='1' else tx_sample;
    rx_reset<=reset or not rx_enable;
    frames_tx<=tx_count; frames_rx<=rx_count; crc_error_frames<=crc_count;
    missing_frames<=missing_count; raw_bit_errors<=raw_errors; raw_bits_checked<=raw_bits;
    payload_bit_errors<=payload_errors; payload_bits_checked<=payload_bits;
    syndrome_word_count<=syndrome_count; sync_acquisitions<=sync_count;
    latency_cycles<=last_latency;
    rx_frame_done<=frame_done; rx_crc_ok<=crc_good;
    rx_sequence<=decoded_seq; rx_payload<=decoded_payload;
    tx : entity work.comm_packet_tx(rtl)
        generic map(INTERLEAVE_DEPTH=>INTERLEAVE_DEPTH,SAMPLES_PER_SYMBOL=>SAMPLES_PER_SYMBOL)
        port map(clk=>clk,reset=>reset,sample_ce=>sample_ce,sample_out=>tx_sample,
                 frame_started=>tx_start,sequence_out=>tx_seq,
                 reference_payload=>tx_payload,reference_body=>tx_body);
    modem_rx : entity work.comm_sample_rx(rtl)
        generic map(SAMPLES_PER_SYMBOL=>SAMPLES_PER_SYMBOL)
        port map(clk=>clk,reset=>rx_reset,sample_ce=>sample_ce,sample_in=>rx_sample,
                 frame_start=>body_start,bit_valid=>demod_valid,bit_out=>demod_bit,
                 locked=>rx_locked,timing_phase=>rx_timing_phase);
    channel : entity work.comm_bit_channel(rtl)
        port map(clk=>clk,reset=>rx_reset,frame_start=>body_start,
                 bit_valid=>demod_valid,bit_in=>demod_bit,error_mode=>error_mode,
                 random_threshold=>random_threshold,burst_start=>burst_start,
                 burst_length=>burst_length,out_valid=>channel_valid,
                 out_bit=>channel_bit,injected=>injected);
    packet_rx : entity work.comm_packet_rx(rtl)
        generic map(INTERLEAVE_DEPTH=>INTERLEAVE_DEPTH)
        port map(clk=>clk,reset=>rx_reset,frame_start=>body_start,
                 bit_valid=>channel_valid,bit_in=>channel_bit,frame_done=>frame_done,
                 crc_ok=>crc_good,sequence_out=>decoded_seq,payload_out=>decoded_payload,
                 syndrome_words=>frame_syndromes);
    process(clk)
        variable delta : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            if reset='1' then
                divider<=0; reference_index<=0; expected_payload<=(others=>'0');
                expected_body<=(others=>'0'); tx_count<=(others=>'0'); rx_count<=(others=>'0');
                crc_count<=(others=>'0'); missing_count<=(others=>'0');
                raw_errors<=(others=>'0'); raw_bits<=(others=>'0');
                payload_errors<=(others=>'0'); payload_bits<=(others=>'0');
                syndrome_count<=(others=>'0'); sync_count<=(others=>'0');
                clock_count<=(others=>'0'); tx_start_cycle<=(others=>'0');
                frame_start_cycle<=(others=>'0'); last_latency<=(others=>'0');
                last_good_seq<=(others=>'0'); have_good_seq<='0';
            else
                if sample_ce='1' then divider<=0; else divider<=divider+1; end if;
                clock_count<=clock_count+1;
                if tx_start='1' then tx_count<=tx_count+1; tx_start_cycle<=clock_count; end if;
                if body_start='1' then
                    expected_payload<=tx_payload; expected_body<=tx_body;
                    reference_index<=0; frame_start_cycle<=tx_start_cycle; sync_count<=sync_count+1;
                end if;
                if channel_valid='1' then
                    raw_bits<=raw_bits+1;
                    if channel_bit/=expected_body(BODY_BITS-1-reference_index) then
                        raw_errors<=raw_errors+1;
                    end if;
                    if reference_index=BODY_BITS-1 then reference_index<=0;
                    else reference_index<=reference_index+1; end if;
                end if;
                if frame_done='1' then
                    rx_count<=rx_count+1;
                    if crc_good='0' then crc_count<=crc_count+1; end if;
                    syndrome_count<=syndrome_count+resize(frame_syndromes,32);
                    payload_bits<=payload_bits+PAYLOAD_BITS;
                    payload_errors<=payload_errors+bit_errors(decoded_payload,expected_payload);
                    last_latency<=clock_count-frame_start_cycle;
                    if crc_good='1' then
                        if have_good_seq='1' then
                            delta:=decoded_seq-last_good_seq;
                            if delta>1 and delta<32768 then
                                missing_count<=missing_count+resize(delta-1,32);
                            end if;
                        end if;
                        last_good_seq<=decoded_seq; have_good_seq<='1';
                    end if;
                end if;
            end if;
        end if;
    end process;
end;
