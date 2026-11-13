-- Combined synthesizable design. Compile this file BEFORE the testbench.
-- Top-level entity: hamming_fsk_link (not the filename).
-- Module logic is unchanged from the original five design files.

-- ====================================================================
-- Original module file: hamming74_encoder.vhd
-- ====================================================================
library ieee;
use ieee.std_logic_1164.all;

entity hamming74_encoder is
    port (
        data_in  : in  std_logic_vector(3 downto 0);
        code_out : out std_logic_vector(6 downto 0)
    );
end hamming74_encoder;

architecture rtl of hamming74_encoder is
begin
    -- Positions 1..7 correspond to vector indices 0..6.
    -- Even parity; data occupies positions 3,5,6,7.
    code_out(0) <= data_in(0) xor data_in(1) xor data_in(3);
    code_out(1) <= data_in(0) xor data_in(2) xor data_in(3);
    code_out(2) <= data_in(0);
    code_out(3) <= data_in(1) xor data_in(2) xor data_in(3);
    code_out(4) <= data_in(1);
    code_out(5) <= data_in(2);
    code_out(6) <= data_in(3);
end rtl;

-- ====================================================================
-- Original module file: hamming74_decoder.vhd
-- ====================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hamming74_decoder is
    port (
        code_in        : in  std_logic_vector(6 downto 0);
        data_out       : out std_logic_vector(3 downto 0);
        corrected_code : out std_logic_vector(6 downto 0);
        syndrome       : out std_logic_vector(2 downto 0);
        error_detected : out std_logic
    );
end hamming74_decoder;

architecture rtl of hamming74_decoder is
begin
    process(code_in)
        variable s : std_logic_vector(2 downto 0);
        variable c : std_logic_vector(6 downto 0);
        variable position : integer range 0 to 7;
    begin
        s(0) := code_in(0) xor code_in(2) xor code_in(4) xor code_in(6);
        s(1) := code_in(1) xor code_in(2) xor code_in(5) xor code_in(6);
        s(2) := code_in(3) xor code_in(4) xor code_in(5) xor code_in(6);
        c := code_in;
        syndrome <= s;
        error_detected <= '0';
        -- Do not convert unknown startup values to an integer.
        if not is_x(s) then
            position := to_integer(unsigned(s));
            if position /= 0 then
                c(position - 1) := not c(position - 1);
                error_detected <= '1';
            end if;
        end if;
        corrected_code <= c;
        data_out <= c(6) & c(5) & c(4) & c(2);
    end process;
end rtl;

-- ====================================================================
-- Original module file: fsk_modulator.vhd
-- ====================================================================
library ieee;
use ieee.std_logic_1164.all;

entity fsk_modulator is
    generic (
        HALF_DIV_0 : positive := 8;
        HALF_DIV_1 : positive := 4
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        bit_start : in  std_logic;
        bit_in    : in  std_logic;
        fsk_out   : out std_logic
    );
end fsk_modulator;

architecture rtl of fsk_modulator is
    function max_int(a, b : positive) return positive is
    begin
        if a > b then return a; else return b; end if;
    end function;
    constant MAX_DIV : positive := max_int(HALF_DIV_0, HALF_DIV_1);
    signal count : natural range 0 to MAX_DIV - 1 := 0;
    signal active_bit : std_logic := '0';
    signal level : std_logic := '0';
begin
    fsk_out <= level;
    process(clk)
        variable half_period : positive;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                count <= 0;
                level <= '0';
                active_bit <= '0';
            elsif bit_start = '1' then
                -- Latch the new symbol and restart phase at its boundary.
                active_bit <= bit_in;
                count <= 0;
                level <= '0';
            else
                if active_bit = '1' then
                    half_period := HALF_DIV_1;
                else
                    half_period := HALF_DIV_0;
                end if;
                if count = half_period - 1 then
                    count <= 0;
                    level <= not level;
                else
                    count <= count + 1;
                end if;
            end if;
        end if;
    end process;
end rtl;

-- ====================================================================
-- Original module file: fsk_demodulator.vhd
-- ====================================================================
library ieee;
use ieee.std_logic_1164.all;

-- Synchronous digital loopback receiver. bit_start supplies the known
-- symbol boundary; this module does not perform timing recovery.
entity fsk_demodulator is
    generic (
        COUNT_THRESHOLD : positive := 6;
        MAX_EDGES       : positive := 64
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        bit_start  : in  std_logic;
        fsk_in     : in  std_logic;
        bit_out    : out std_logic;
        bit_valid  : out std_logic;
        edge_count : out natural range 0 to MAX_EDGES
    );
end fsk_demodulator;

architecture rtl of fsk_demodulator is
    signal previous_sample : std_logic := '0';
    signal counter : natural range 0 to MAX_EDGES := 0;
    signal active : std_logic := '0';
begin
    process(clk)
        variable total : natural range 0 to MAX_EDGES;
    begin
        if rising_edge(clk) then
            if reset = '1' then
                previous_sample <= '0';
                counter <= 0;
                active <= '0';
                bit_out <= '0';
                bit_valid <= '0';
                edge_count <= 0;
            else
                previous_sample <= fsk_in;
                bit_valid <= '0';
                total := counter;
                if active = '1' and previous_sample = '0' and fsk_in = '1' then
                    if total < MAX_EDGES then total := total + 1; end if;
                end if;
                if bit_start = '1' then
                    if active = '1' then
                        edge_count <= total;
                        if total >= COUNT_THRESHOLD then
                            bit_out <= '1';
                        else
                            bit_out <= '0';
                        end if;
                        bit_valid <= '1';
                    end if;
                    counter <= 0;
                    active <= '1';
                else
                    counter <= total;
                end if;
            end if;
        end if;
    end process;
end rtl;

-- ====================================================================
-- Original module file: hamming_fsk_link.vhd
-- ====================================================================
library ieee;
use ieee.std_logic_1164.all;

-- Single-clock, known-boundary DIGITAL loopback. No ADC/DAC interface.
entity hamming_fsk_link is
    port (
        clk            : in  std_logic;
        reset          : in  std_logic;
        start          : in  std_logic;
        data_in        : in  std_logic_vector(3 downto 0);
        error_mask     : in  std_logic_vector(6 downto 0);
        busy           : out std_logic;
        done           : out std_logic;
        code_tx        : out std_logic_vector(6 downto 0);
        raw_code_rx    : out std_logic_vector(6 downto 0);
        code_rx        : out std_logic_vector(6 downto 0);
        corrected_code : out std_logic_vector(6 downto 0);
        data_out       : out std_logic_vector(3 downto 0);
        syndrome       : out std_logic_vector(2 downto 0);
        error_detected : out std_logic;
        bit_start      : out std_logic;
        tx_bit         : out std_logic;
        fsk_signal     : out std_logic;
        rx_bit         : out std_logic;
        rx_bit_valid   : out std_logic
    );
end hamming_fsk_link;

architecture rtl of hamming_fsk_link is
    type state_type is (IDLE, SEND_BITS, FLUSH_LAST, SETTLE, FINISH);
    signal state : state_type := IDLE;
    signal encoded : std_logic_vector(6 downto 0);
    signal tx_word : std_logic_vector(6 downto 0) := (others => '0');
    signal mask_latched : std_logic_vector(6 downto 0) := (others => '0');
    signal symbol_index : integer range 0 to 6 := 6;
    signal phase : integer range 0 to 63 := 0;
    signal boundary : std_logic;
    signal serial_tx, carrier, serial_rx, valid_rx : std_logic;
    signal rx_shift : std_logic_vector(6 downto 0) := (others => '0');
    signal rx_count : integer range 0 to 7 := 0;
    signal rx_word : std_logic_vector(6 downto 0) := (others => '0');
    signal decoded : std_logic_vector(3 downto 0);
    signal corrected : std_logic_vector(6 downto 0);
    signal syn : std_logic_vector(2 downto 0);
    signal detected : std_logic;
    signal modem_reset : std_logic;
begin
    enc : entity work.hamming74_encoder(rtl)
        port map(data_in => data_in, code_out => encoded);
    boundary <= '1' when (state = SEND_BITS or state = FLUSH_LAST) and phase = 0 else '0';
    serial_tx <= tx_word(symbol_index) when state = SEND_BITS else '0';
    -- Reset receiver history between frames. Counters restart on first boundary.
    modem_reset <= '1' when reset = '1' or state = IDLE else '0';
    tx : entity work.fsk_modulator(rtl)
        generic map(HALF_DIV_0 => 8, HALF_DIV_1 => 4)
        port map(clk => clk, reset => modem_reset, bit_start => boundary,
                 bit_in => serial_tx, fsk_out => carrier);
    rx : entity work.fsk_demodulator(rtl)
        generic map(COUNT_THRESHOLD => 6, MAX_EDGES => 64)
        port map(clk => clk, reset => modem_reset, bit_start => boundary,
                 fsk_in => carrier, bit_out => serial_rx,
                 bit_valid => valid_rx, edge_count => open);
    dec : entity work.hamming74_decoder(rtl)
        port map(code_in => rx_word, data_out => decoded,
                 corrected_code => corrected, syndrome => syn,
                 error_detected => detected);

    code_tx <= tx_word;
    code_rx <= rx_word;
    bit_start <= boundary;
    tx_bit <= serial_tx;
    fsk_signal <= carrier;
    rx_bit <= serial_rx;
    rx_bit_valid <= valid_rx;

    process(clk)
        variable assembled : std_logic_vector(6 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                phase <= 0;
                symbol_index <= 6;
                tx_word <= (others => '0');
                mask_latched <= (others => '0');
                rx_shift <= (others => '0');
                rx_count <= 0;
                rx_word <= (others => '0');
                busy <= '0'; done <= '0';
                raw_code_rx <= (others => '0');
                corrected_code <= (others => '0');
                data_out <= (others => '0');
                syndrome <= (others => '0');
                error_detected <= '0';
            else
                done <= '0';
                if valid_rx = '1' and (state = SEND_BITS or state = FLUSH_LAST) then
                    assembled := rx_shift(5 downto 0) & serial_rx;
                    rx_shift <= assembled;
                    if rx_count < 7 then rx_count <= rx_count + 1; end if;
                    if rx_count = 6 then
                        raw_code_rx <= assembled;
                        -- Explicit post-demodulation fault injection, NOT analog noise.
                        rx_word <= assembled xor mask_latched;
                    end if;
                end if;
                case state is
                    when IDLE =>
                        busy <= '0';
                        if start = '1' then
                            tx_word <= encoded;
                            mask_latched <= error_mask;
                            rx_shift <= (others => '0');
                            rx_count <= 0;
                            symbol_index <= 6;
                            phase <= 0;
                            busy <= '1';
                            state <= SEND_BITS;
                        end if;
                    when SEND_BITS =>
                        if phase = 63 then
                            phase <= 0;
                            if symbol_index = 0 then state <= FLUSH_LAST;
                            else symbol_index <= symbol_index - 1; end if;
                        else phase <= phase + 1; end if;
                    when FLUSH_LAST =>
                        if phase < 63 then phase <= phase + 1; end if;
                        if valid_rx = '1' and rx_count = 6 then
                            state <= SETTLE;
                        end if;
                    when SETTLE =>
                        -- Let the combinational Hamming decoder settle.
                        state <= FINISH;
                    when FINISH =>
                        data_out <= decoded;
                        corrected_code <= corrected;
                        syndrome <= syn;
                        error_detected <= detected;
                        done <= '1'; busy <= '0';
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;
end rtl;

