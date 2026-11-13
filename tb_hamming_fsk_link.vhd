library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hamming_fsk_link is end tb_hamming_fsk_link;
architecture sim of tb_hamming_fsk_link is
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal start : std_logic := '0';
    signal data_in, data_out : std_logic_vector(3 downto 0) := (others => '0');
    signal error_mask, code_tx, raw_code_rx, code_rx, corrected_code :
        std_logic_vector(6 downto 0) := (others => '0');
    signal syndrome : std_logic_vector(2 downto 0);
    signal busy, done, error_detected : std_logic;
    signal bit_start, tx_bit, fsk_signal, rx_bit, rx_bit_valid : std_logic;
    signal test_done : boolean := false;
begin
    dut : entity work.hamming_fsk_link(rtl)
        port map(clk => clk, reset => reset, start => start, data_in => data_in,
            error_mask => error_mask, busy => busy, done => done, code_tx => code_tx,
            raw_code_rx => raw_code_rx, code_rx => code_rx, corrected_code => corrected_code,
            data_out => data_out, syndrome => syndrome, error_detected => error_detected,
            bit_start => bit_start, tx_bit => tx_bit, fsk_signal => fsk_signal,
            rx_bit => rx_bit, rx_bit_valid => rx_bit_valid);
    clock_gen : process
    begin
        while not test_done loop
            clk <= '0'; wait for 5 ns;
            clk <= '1'; wait for 5 ns;
        end loop;
        clk <= '0'; wait;
    end process;
    stimulus : process
        variable failures : natural := 0;
        variable cases_done : natural := 0;
        procedure run_case(constant value : in natural;
                           constant position : in natural) is
            variable mask_v : std_logic_vector(6 downto 0);
            variable completed : boolean;
            variable expected_flag : std_logic;
        begin
            wait until falling_edge(clk);
            data_in <= std_logic_vector(to_unsigned(value, 4));
            mask_v := (others => '0');
            if position > 0 then mask_v(position-1) := '1'; end if;
            error_mask <= mask_v;
            start <= '1';
            wait until falling_edge(clk);
            start <= '0';
            completed := false;
            for cycle in 1 to 600 loop
                wait until rising_edge(clk);
                wait for 1 ns;
                if done = '1' then completed := true; exit; end if;
            end loop;
            if not completed then
                failures := failures + 1;
                assert false report "Frame timeout" severity failure;
            end if;
            if position = 0 then expected_flag := '0'; else expected_flag := '1'; end if;
            if data_out /= std_logic_vector(to_unsigned(value, 4)) or
               raw_code_rx /= code_tx or code_rx /= (code_tx xor mask_v) or
               corrected_code /= code_tx or
               syndrome /= std_logic_vector(to_unsigned(position, 3)) or
               error_detected /= expected_flag or busy /= '0' then
                failures := failures + 1;
                assert false report "End-to-end mismatch: input=" & integer'image(value) &
                    " error position=" & integer'image(position) severity error;
            end if;
            cases_done := cases_done + 1;
        end procedure;
    begin
        wait for 40 ns;
        wait until falling_edge(clk);
        reset <= '0';
        -- First two frames are the easy-to-read demonstration.
        run_case(11, 0);
        report "Demo 1 completed: data=1011, no injected error." severity note;
        run_case(11, 3);
        report "Demo 2 completed: data=1011, injected error at position 3." severity note;
        -- Exhaustive test of 16 inputs and clean/7 single-bit-error cases.
        for value in 0 to 15 loop
            for position in 0 to 7 loop
                run_case(value, position);
            end loop;
        end loop;
        if failures = 0 then
            report "All 130 end-to-end frames checked successfully." severity note;
        else
            assert false report "End-to-end test FAILED" severity error;
        end if;
        test_done <= true;
        wait;
    end process;
end sim;
