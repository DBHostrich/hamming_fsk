library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

entity tb_comm_codec is end;
architecture sim of tb_comm_codec is
begin
    process
        type depths_t is array(0 to 2) of positive;
        constant depths : depths_t := (1,4,8);
        constant check_text : string := "123456789";
        variable c,bad : code_t;
        variable info,recovered : info_t;
        variable encoded,wire_body,damaged,deinterleaved : body_t;
        variable crc : crc_t;
        variable byte : unsigned(7 downto 0);
        variable checks,failures_seen : natural := 0;
    begin
        -- Published CRC-16/CCITT-FALSE check value, independent of packet code.
        crc:=x"FFFF";
        for k in check_text'range loop
            byte:=to_unsigned(character'pos(check_text(k)),8);
            for i in 7 downto 0 loop crc:=crc_step(crc,byte(i)); end loop;
        end loop;
        assert crc=x"29B1" report "CRC known-answer test failed" severity failure;
        assert hamming_encode(x"B")="1010101" report "Hamming bit order changed" severity failure;
        for d in 0 to 15 loop
            c:=hamming_encode(std_logic_vector(to_unsigned(d,4)));
            for error_pos in 0 to 7 loop
                bad:=c;
                if error_pos>0 then bad(error_pos-1):=not bad(error_pos-1); end if;
                assert hamming_decode(bad)=std_logic_vector(to_unsigned(d,4))
                    report "Single-error correction failed" severity failure;
                assert hamming_syndrome(bad)=error_pos
                    report "Syndrome position failed" severity failure;
                checks:=checks+1;
            end loop;
        end loop;
        -- All burst locations, including interleaver-block boundaries.
        for seed in 0 to 3 loop
            info:=make_info(to_unsigned(seed*1031,16)); encoded:=encode_info(info);
            for mode in depths'range loop
                wire_body:=interleave_body(encoded,depths(mode));
                for length in 1 to 10 loop
                    for first in 0 to BODY_BITS-length loop
                        damaged:=wire_body;
                        for j in first to first+length-1 loop
                            damaged(BODY_BITS-1-j):=not damaged(BODY_BITS-1-j);
                        end loop;
                        for j in 0 to BODY_BITS-1 loop
                            deinterleaved(BODY_BITS-1-interleave_source(j,depths(mode))):=
                                damaged(BODY_BITS-1-j);
                        end loop;
                        for w in 0 to CODEWORDS-1 loop
                            recovered(INFO_BITS-1-4*w downto INFO_BITS-4-4*w):=
                                hamming_decode(deinterleaved(BODY_BITS-1-7*w downto BODY_BITS-7-7*w));
                        end loop;
                        if length<=depths(mode) then
                            assert recovered=info report "Interleaver burst guarantee failed" severity failure;
                        elsif recovered/=info then failures_seen:=failures_seen+1; end if;
                        checks:=checks+1;
                    end loop;
                end loop;
            end loop;
        end loop;
        assert failures_seen>0 report "No beyond-capability cases exercised" severity failure;
        report "PASS codec: "&integer'image(checks)&" checks; beyond-capability failures observed="&
               integer'image(failures_seen) severity note;
        wait;
    end process;
end;
