library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

entity comm_packet_rx is
    generic (INTERLEAVE_DEPTH : positive := 8);
    port (clk,reset,frame_start,bit_valid,bit_in : in std_logic;
          frame_done,crc_ok : out std_logic;
          sequence_out : out unsigned(15 downto 0);
          payload_out : out payload_t;
          syndrome_words : out unsigned(5 downto 0));
end;
architecture rtl of comm_packet_rx is
    type state_t is (WAIT_SYNC,COLLECT,DECODE,CHECK_CRC,FINISH);
    signal state : state_t := WAIT_SYNC;
    signal received_body : body_t := (others=>'0');
    signal info : info_t := (others=>'0');
    signal bit_index : natural range 0 to BODY_BITS-1 := 0;
    signal word_index : natural range 0 to CODEWORDS-1 := 0;
    signal crc_index : natural range 0 to 143 := 0;
    signal crc : crc_t := x"FFFF";
    signal syndromes : unsigned(5 downto 0) := (others=>'0');
begin
    assert INTERLEAVE_DEPTH=1 or INTERLEAVE_DEPTH=4 or INTERLEAVE_DEPTH=8
        report "Invalid interleave depth" severity failure;
    process(clk)
        variable c : code_t;
        variable next_crc : crc_t;
    begin
        if rising_edge(clk) then
            frame_done<='0';
            if reset='1' then
                state<=WAIT_SYNC; received_body<=(others=>'0'); info<=(others=>'0');
                bit_index<=0; word_index<=0; crc_index<=0; crc<=x"FFFF";
                syndromes<=(others=>'0'); syndrome_words<=(others=>'0');
                sequence_out<=(others=>'0'); payload_out<=(others=>'0'); crc_ok<='0';
            elsif frame_start='1' then
                state<=COLLECT; bit_index<=0; syndromes<=(others=>'0'); crc_ok<='0';
            else
                case state is
                    when WAIT_SYNC => null;
                    when COLLECT =>
                        if bit_valid='1' then
                            received_body(BODY_BITS-1-interleave_source(bit_index,INTERLEAVE_DEPTH))<=bit_in;
                            if bit_index=BODY_BITS-1 then word_index<=0; state<=DECODE;
                            else bit_index<=bit_index+1; end if;
                        end if;
                    when DECODE =>
                        c:=received_body(BODY_BITS-1-7*word_index downto BODY_BITS-7-7*word_index);
                        info(INFO_BITS-1-4*word_index downto INFO_BITS-4-4*word_index)<=hamming_decode(c);
                        if hamming_syndrome(c)/=0 then syndromes<=syndromes+1; end if;
                        if word_index=CODEWORDS-1 then
                            crc_index<=0; crc<=x"FFFF"; state<=CHECK_CRC;
                        else word_index<=word_index+1; end if;
                    when CHECK_CRC =>
                        next_crc:=crc_step(crc,info(INFO_BITS-1-crc_index)); crc<=next_crc;
                        if crc_index=143 then
                            if next_crc=unsigned(info(15 downto 0)) then crc_ok<='1';
                            else crc_ok<='0'; end if;
                            state<=FINISH;
                        else crc_index<=crc_index+1; end if;
                    when FINISH =>
                        sequence_out<=unsigned(info(159 downto 144)); payload_out<=info(143 downto 16);
                        syndrome_words<=syndromes; frame_done<='1'; state<=WAIT_SYNC;
                end case;
            end if;
        end if;
    end process;
end;
