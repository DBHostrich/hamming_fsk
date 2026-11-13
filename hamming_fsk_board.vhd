library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- V2 board: active-low reset button, active-high LEDs.
entity hamming_fsk_board is
    port (
        sys_clk : in  std_logic;
        reset   : in  std_logic;
        led_1   : out std_logic_vector(0 to 7);
        led_2   : out std_logic_vector(0 to 7)
    );
end hamming_fsk_board;

architecture rtl of hamming_fsk_board is
    type state_type is (ISSUE, WAIT_FRAME, SHOW_RESULTS);
    constant DEMO_DATA : unsigned(3 downto 0) := "1011";
    constant DEMO_ERROR_POSITION : natural := 3;
    signal reset_meta, reset_sync : std_logic := '1';
    signal state : state_type := ISSUE;
    signal payload : unsigned(3 downto 0) := (others => '0');
    signal error_position : natural range 0 to 7 := 0;
    signal error_mask, tx_code, raw_code, received_code, corrected_code :
        std_logic_vector(6 downto 0);
    signal data_out : std_logic_vector(3 downto 0);
    signal syndrome : std_logic_vector(2 downto 0);
    signal start, done, detected, expected_detected : std_logic;
    signal clean_display, error_display : std_logic_vector(6 downto 0) := (others => '0');
    signal clean_ok, correction_ok : std_logic := '1';
    signal clean_pass, correction_pass : std_logic;
begin
    process(sys_clk)
    begin
        if rising_edge(sys_clk) then
            reset_meta <= not reset;
            reset_sync <= reset_meta;
        end if;
    end process;

    start <= '1' when state = ISSUE else '0';
    expected_detected <= '0' when error_position = 0 else '1';
    error_mask <= (others => '0') when error_position = 0 else
                  std_logic_vector(shift_left(to_unsigned(1, 7), error_position - 1));

    link : entity work.hamming_fsk_link(rtl)
        port map (
            clk => sys_clk, reset => reset_sync, start => start,
            data_in => std_logic_vector(payload), error_mask => error_mask,
            busy => open, done => done, code_tx => tx_code, raw_code_rx => raw_code,
            code_rx => received_code, corrected_code => corrected_code,
            data_out => data_out, syndrome => syndrome, error_detected => detected,
            bit_start => open, tx_bit => open, fsk_signal => open,
            rx_bit => open, rx_bit_valid => open
        );

    -- LED order on the board: four data bits (MSB first), three syndrome bits,
    -- then an aggregate pass light that turns on only after the entire sweep.
    clean_pass <= clean_ok when state = SHOW_RESULTS else '0';
    correction_pass <= correction_ok when state = SHOW_RESULTS else '0';
    led_1 <= clean_display & clean_pass;
    led_2 <= error_display & correction_pass;

    process(sys_clk)
        variable frame_ok : boolean;
    begin
        if rising_edge(sys_clk) then
            if reset_sync = '1' then
                state <= ISSUE;
                payload <= (others => '0');
                error_position <= 0;
                clean_display <= (others => '0');
                error_display <= (others => '0');
                clean_ok <= '1';
                correction_ok <= '1';
            else
                case state is
                    when ISSUE =>
                        state <= WAIT_FRAME;
                    when WAIT_FRAME =>
                        if done = '1' then
                            frame_ok := data_out = std_logic_vector(payload) and
                                        raw_code = tx_code and
                                        received_code = (tx_code xor error_mask) and
                                        corrected_code = tx_code and
                                        unsigned(syndrome) = error_position and
                                        detected = expected_detected;
                            if error_position = 0 then
                                if not frame_ok then clean_ok <= '0'; end if;
                                if payload = DEMO_DATA then clean_display <= data_out & syndrome; end if;
                            else
                                if not frame_ok then correction_ok <= '0'; end if;
                                if payload = DEMO_DATA and error_position = DEMO_ERROR_POSITION then
                                    error_display <= data_out & syndrome;
                                end if;
                            end if;

                            if error_position < 7 then
                                error_position <= error_position + 1;
                                state <= ISSUE;
                            elsif payload /= 15 then
                                error_position <= 0;
                                payload <= payload + 1;
                                state <= ISSUE;
                            else
                                state <= SHOW_RESULTS;
                            end if;
                        end if;
                    when SHOW_RESULTS =>
                        null;
                end case;
            end if;
        end if;
    end process;
end rtl;
