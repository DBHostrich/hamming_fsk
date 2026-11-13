library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

entity comm_packet_tx is
    generic (INTERLEAVE_DEPTH : positive := 8; SAMPLES_PER_SYMBOL : positive := 128;
             GAP_SYMBOLS : positive := 4);
    port (clk, reset, sample_ce : in std_logic;
          sample_out : out sample_t;
          frame_started : out std_logic;
          sequence_out : out unsigned(15 downto 0);
          reference_payload : out payload_t;
          reference_body : out body_t);
end;

architecture rtl of comm_packet_tx is
    type state_t is (PREPARE, PAYLOAD_BUILD, CRC_BUILD, ENCODE,
                     TRAIN, SYNC, DATA, GAP);
    signal state : state_t := PREPARE;
    signal seq : unsigned(15 downto 0) := (others=>'0');
    signal info : info_t := (others=>'0');
    signal encoded : body_t := (others=>'0');
    signal lfsr : unsigned(15 downto 0) := x"1D0F";
    signal crc : crc_t := x"FFFF";
    signal build_index : natural range 0 to INFO_BITS-1 := 0;
    signal symbol_index : natural range 0 to BODY_BITS-1 := 0;
    signal sample_index : natural range 0 to SAMPLES_PER_SYMBOL-1 := 0;
    signal wave_phase : natural range 0 to 31 := 0;
    signal gap_index : natural range 0 to GAP_SYMBOLS-1 := 0;
    signal symbol : std_logic;
begin
    assert INTERLEAVE_DEPTH=1 or INTERLEAVE_DEPTH=4 or INTERLEAVE_DEPTH=8
        report "Supported interleave depths: 1 (bypass), 4, 8" severity failure;
    assert SAMPLES_PER_SYMBOL >= 32 and SAMPLES_PER_SYMBOL mod 32 = 0
        report "SAMPLES_PER_SYMBOL must be a multiple of 32" severity failure;
    sequence_out <= seq;
    reference_payload <= info(143 downto 16);
    reference_body <= interleave_body(encoded,INTERLEAVE_DEPTH);
    process(state,symbol_index,encoded)
    begin
        symbol <= '0';
        case state is
            when TRAIN =>
                if symbol_index mod 2 = 1 then symbol <= '1'; end if;
            when SYNC => symbol <= SYNC_WORD(SYNC_BITS-1-symbol_index);
            when DATA => symbol <= encoded(BODY_BITS-1-interleave_source(symbol_index,INTERLEAVE_DEPTH));
            when others => null;
        end case;
    end process;
    process(clk)
        variable next_crc : crc_t;
    begin
        if rising_edge(clk) then
            frame_started <= '0';
            if reset='1' then
                state<=PREPARE; seq<=(others=>'0'); info<=(others=>'0');
                encoded<=(others=>'0'); crc<=x"FFFF"; lfsr<=x"1D0F";
                sample_out<=(others=>'0'); build_index<=0; symbol_index<=0;
                sample_index<=0; wave_phase<=0; gap_index<=0;
            else
                case state is
                    when PREPARE =>
                        info(159 downto 144)<=std_logic_vector(seq);
                        lfsr<=payload_seed(seq); build_index<=0; state<=PAYLOAD_BUILD;
                    when PAYLOAD_BUILD =>
                        info(143-build_index)<=lfsr(15); lfsr<=prbs_next(lfsr);
                        if build_index=127 then
                            build_index<=0; crc<=x"FFFF"; state<=CRC_BUILD;
                        else build_index<=build_index+1; end if;
                    when CRC_BUILD =>
                        next_crc:=crc_step(crc,info(159-build_index)); crc<=next_crc;
                        if build_index=143 then
                            info(15 downto 0)<=std_logic_vector(next_crc);
                            build_index<=0; state<=ENCODE;
                        else build_index<=build_index+1; end if;
                    when ENCODE =>
                        encoded(BODY_BITS-1-7*build_index downto BODY_BITS-7-7*build_index)<=
                            hamming_encode(info(INFO_BITS-1-4*build_index downto INFO_BITS-4-4*build_index));
                        if build_index=CODEWORDS-1 then
                            symbol_index<=0; sample_index<=0; wave_phase<=0;
                            frame_started<='1'; state<=TRAIN;
                        else build_index<=build_index+1; end if;
                    when TRAIN | SYNC | DATA =>
                        if sample_ce='1' then
                            sample_out<=to_signed(SINE32(wave_phase),8);
                            if symbol='1' then wave_phase<=(wave_phase+2) mod 32;
                            else wave_phase<=(wave_phase+1) mod 32; end if;
                            if sample_index=SAMPLES_PER_SYMBOL-1 then
                                sample_index<=0;
                                if (state=TRAIN and symbol_index=TRAIN_BITS-1) or
                                   (state=SYNC and symbol_index=SYNC_BITS-1) or
                                   (state=DATA and symbol_index=BODY_BITS-1) then
                                    symbol_index<=0;
                                    if state=TRAIN then state<=SYNC;
                                    elsif state=SYNC then state<=DATA;
                                    else state<=GAP; gap_index<=0; end if;
                                else symbol_index<=symbol_index+1; end if;
                            else sample_index<=sample_index+1; end if;
                        end if;
                    when GAP =>
                        if sample_ce='1' then
                            sample_out<=(others=>'0');
                            if sample_index=SAMPLES_PER_SYMBOL-1 then
                                sample_index<=0;
                                if gap_index=GAP_SYMBOLS-1 then seq<=seq+1; state<=PREPARE;
                                else gap_index<=gap_index+1; end if;
                            else sample_index<=sample_index+1; end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end rtl;
