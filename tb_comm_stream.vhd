library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

entity tb_comm_stream is
    generic (DEPTH : positive := 8);
end;
architecture sim of tb_comm_stream is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal rx_enable : std_logic := '0';
    signal mode : unsigned(1 downto 0) := "00";
    signal threshold : unsigned(15 downto 0) := (others=>'0');
    signal burst_length : natural range 0 to BODY_BITS := 4;
    signal sample_ce,frame_done,crc_good,locked : std_logic;
    signal tx_sample : sample_t;
    signal seq : unsigned(15 downto 0);
    signal payload : payload_t;
    signal phase : unsigned(7 downto 0);
    signal tx_count,rx_count,crc_count,missing_count,raw_errors,raw_bits,
           payload_errors,payload_bits,syndromes,sync_count,latency : count_t;
    signal finished : boolean := false;
begin
    -- Accelerated sampling: only the CE divisor changes, not the modem's
    -- samples/symbol or carrier ratios. Board uses SAMPLE_DIV=32.
    dut : entity work.hamming_fsk_stream(rtl)
        generic map(INTERLEAVE_DEPTH=>DEPTH,SAMPLE_DIV=>1,SAMPLES_PER_SYMBOL=>128)
        port map(clk=>clk,reset=>reset,rx_enable=>rx_enable,external_rx=>'0',
                 rx_sample_in=>to_signed(0,8),error_mode=>mode,random_threshold=>threshold,
                 burst_start=>70,burst_length=>burst_length,sample_ce_out=>sample_ce,
                 tx_sample_out=>tx_sample,rx_frame_done=>frame_done,rx_crc_ok=>crc_good,
                 rx_locked=>locked,rx_sequence=>seq,rx_payload=>payload,rx_timing_phase=>phase,
                 frames_tx=>tx_count,frames_rx=>rx_count,crc_error_frames=>crc_count,
                 missing_frames=>missing_count,raw_bit_errors=>raw_errors,raw_bits_checked=>raw_bits,
                 payload_bit_errors=>payload_errors,payload_bits_checked=>payload_bits,
                 syndrome_word_count=>syndromes,sync_acquisitions=>sync_count,latency_cycles=>latency);
    clock_gen : process
    begin
        while not finished loop clk<='0'; wait for 5 ns; clk<='1'; wait for 5 ns; end loop;
        wait;
    end process;
    stimulus : process
        variable before_crc,before_errors,before_rx,before_missing : count_t;
        variable previous_seq : unsigned(15 downto 0);
        procedure step(constant cycles : natural) is
        begin
            for i in 1 to cycles loop wait until rising_edge(clk); wait for 1 ns; end loop;
        end;
        procedure receive_frame is
            variable completed : boolean := false;
        begin
            for i in 1 to 160000 loop
                wait until rising_edge(clk); wait for 1 ns;
                if frame_done='1' then completed:=true; exit; end if;
            end loop;
            assert completed report "Autonomous RX timeout" severity failure;
            -- Statistics update on the following clock edge.
            step(1);
        end;
        procedure check_clean_frame is
        begin
            receive_frame;
            assert crc_good='1' report "Clean frame CRC failed" severity failure;
            assert payload=make_payload(seq) report "Clean payload mismatch" severity failure;
        end;
    begin
        step(8); reset<='0';
        -- Receiver starts halfway through a transmitted frame.
        step(23017); rx_enable<='1';
        check_clean_frame; previous_seq:=seq;
        for f in 1 to 3 loop
            check_clean_frame;
            assert seq=previous_seq+1 report "Sequence discontinuity" severity failure;
            previous_seq:=seq;
        end loop;
        assert raw_errors=0 and payload_errors=0 and crc_count=0
            report "Clean link accumulated errors" severity failure;
        assert payload_bits=rx_count*PAYLOAD_BITS report "Payload counter mismatch" severity failure;
        assert raw_bits=rx_count*BODY_BITS report "Raw bit counter mismatch" severity failure;

        -- Mode changes latch at the next acquired frame. Currently between
        -- frames, so every subsequent frame receives exactly four flips.
        mode<="10"; before_crc:=crc_count; before_errors:=raw_errors; before_rx:=rx_count;
        for f in 1 to 4 loop receive_frame; end loop;
        assert raw_errors-before_errors=16 report "Burst injection count mismatch" severity failure;
        assert rx_count-before_rx=4 report "Frame count mismatch" severity failure;
        if DEPTH=1 then
            assert crc_count-before_crc=4 and payload_errors>0
                report "Bypass did not expose uncorrectable burst" severity failure;
        else
            assert crc_count=before_crc and payload_errors=0
                report "Depth 4/8 failed to correct a four-bit burst" severity failure;
        end if;

        -- Longer than the selected depth: must exercise failures, rather
        -- than incorrectly claim that Hamming corrects arbitrary bursts.
        burst_length<=16; before_crc:=crc_count;
        for f in 1 to 3 loop receive_frame; end loop;
        assert crc_count>before_crc report "Beyond-capability CRC failures absent" severity failure;

        mode<="01"; threshold<=to_unsigned(8192,16); before_errors:=raw_errors;
        for f in 1 to 6 loop receive_frame; end loop;
        assert raw_errors>before_errors report "Random fault generator inactive" severity failure;

        mode<="00"; threshold<=(others=>'0');
        for f in 1 to 2 loop check_clean_frame; end loop;
        before_missing:=missing_count; rx_enable<='0'; step(120003); rx_enable<='1';
        check_clean_frame;
        assert missing_count>before_missing report "Missed frames not counted after reacquisition" severity failure;
        assert sync_count>=rx_count report "Acquisition counter mismatch" severity failure;
        assert latency>0 report "Latency counter inactive" severity failure;
        report "PASS stream depth="&integer'image(DEPTH)&
               " received="&integer'image(to_integer(rx_count))&
               " crc_errors="&integer'image(to_integer(crc_count))&
               " raw_bit_errors="&integer'image(to_integer(raw_errors)) severity note;
        finished<=true;
        wait;
    end process;
end;
