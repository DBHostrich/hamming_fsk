library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

-- Errors affect the received, still-interleaved body, not the preamble.
-- mode: 0 clean, 1 pseudorandom, 2 one burst per frame, 3 random OR burst.
entity comm_bit_channel is
    port (clk,reset,frame_start,bit_valid,bit_in : in std_logic;
          error_mode : in unsigned(1 downto 0);
          random_threshold : in unsigned(15 downto 0);
          burst_start : in natural range 0 to BODY_BITS-1;
          burst_length : in natural range 0 to BODY_BITS;
          out_valid,out_bit,injected : out std_logic);
end;
architecture rtl of comm_bit_channel is
    signal index : natural range 0 to BODY_BITS-1 := 0;
    signal random_state : unsigned(15 downto 0) := x"ACE1";
    signal mode : unsigned(1 downto 0) := "00";
    signal threshold : unsigned(15 downto 0) := (others=>'0');
    signal start_at : natural range 0 to BODY_BITS-1 := 0;
    signal length : natural range 0 to BODY_BITS := 0;
begin
    process(clk)
        variable flip : boolean;
    begin
        if rising_edge(clk) then
            out_valid<='0'; injected<='0';
            if reset='1' then
                index<=0; random_state<=x"ACE1"; mode<="00";
                threshold<=(others=>'0'); start_at<=0; length<=0; out_bit<='0';
            elsif frame_start='1' then
                index<=0; mode<=error_mode; threshold<=random_threshold;
                start_at<=burst_start; length<=burst_length;
            elsif bit_valid='1' then
                flip:=false;
                if mode="01" or mode="11" then flip:=random_state<threshold; end if;
                if mode="10" or mode="11" then
                    flip:=flip or (index>=start_at and index<start_at+length);
                end if;
                random_state<=prbs_next(random_state);
                out_bit<=bit_in; out_valid<='1';
                if flip then out_bit<=not bit_in; injected<='1'; end if;
                if index=BODY_BITS-1 then index<=0; else index<=index+1; end if;
            end if;
        end if;
    end process;
end;
