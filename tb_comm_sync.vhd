library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

entity tb_comm_sync is
    generic (PHASE_CASES : positive := 128);
end;
architecture sim of tb_comm_sync is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal rx_reset : std_logic := '1';
    signal tx_sample,impaired_sample : sample_t;
    signal tx_start,body_start,bit_valid,bit_value,locked,frame_done,crc_good : std_logic;
    signal tx_seq,rx_seq : unsigned(15 downto 0);
    signal payload : payload_t;
    signal phase : unsigned(7 downto 0);
    signal noise_state : unsigned(15 downto 0) := x"BEEF";
    signal finished : boolean := false;
begin
    tx : entity work.comm_packet_tx(rtl)
        port map(clk=>clk,reset=>reset,sample_ce=>'1',sample_out=>tx_sample,
                 frame_started=>tx_start,sequence_out=>tx_seq,
                 reference_payload=>open,reference_body=>open);
    -- A receiver sees attenuated samples and small additive integer noise.
    -- This is a bounded digital impairment, not a calibrated AWGN channel.
    impaired_sample<=to_signed(0,8) when reset='1' else
        to_signed(to_integer(tx_sample)/2+to_integer(noise_state(2 downto 0))-3,8);
    modem : entity work.comm_sample_rx(rtl)
        port map(clk=>clk,reset=>rx_reset,sample_ce=>'1',sample_in=>impaired_sample,
                 frame_start=>body_start,bit_valid=>bit_valid,bit_out=>bit_value,
                 locked=>locked,timing_phase=>phase);
    packet : entity work.comm_packet_rx(rtl)
        port map(clk=>clk,reset=>rx_reset,frame_start=>body_start,
                 bit_valid=>bit_valid,bit_in=>bit_value,frame_done=>frame_done,
                 crc_ok=>crc_good,sequence_out=>rx_seq,payload_out=>payload,syndrome_words=>open);
    clock_gen : process
    begin
        while not finished loop clk<='0'; wait for 5 ns; clk<='1'; wait for 5 ns; end loop;
        wait;
    end process;
    process(clk)
    begin
        if rising_edge(clk) then noise_state<=prbs_next(noise_state); end if;
    end process;
    process
        variable completed,started : boolean;
        procedure step(constant n : natural) is
        begin
            for i in 1 to n loop wait until rising_edge(clk); wait for 1 ns; end loop;
        end;
    begin
        assert PHASE_CASES<=128 report "PHASE_CASES must be <=128" severity failure;
        step(8); reset<='0';
        for offset in 0 to PHASE_CASES-1 loop
            rx_reset<='1'; started:=false;
            -- Only the testbench uses TX start to schedule a controlled trial.
            -- Neither receiver entity receives this signal.
            for i in 1 to 100000 loop
                step(1);
                if tx_start='1' then started:=true; exit; end if;
            end loop;
            assert started report "Transmitter stalled" severity failure;
            step(57*128+offset); rx_reset<='0'; completed:=false;
            for i in 1 to 160000 loop
                step(1);
                if frame_done='1' then completed:=true; exit; end if;
            end loop;
            assert completed report "Timing acquisition timeout at offset="&integer'image(offset) severity failure;
            assert crc_good='1' and payload=make_payload(rx_seq)
                report "Acquisition/payload failed at offset="&integer'image(offset) severity failure;
        end loop;
        report "PASS sync: "&integer'image(PHASE_CASES)&
               " startup offsets with attenuation and bounded sample noise" severity note;
        finished<=true; wait;
    end process;
end;
