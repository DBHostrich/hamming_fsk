library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package comm_stream_pkg is
    constant PAYLOAD_BITS : positive := 128;
    constant INFO_BITS : positive := 160;
    constant CODEWORDS : positive := INFO_BITS / 4;
    constant BODY_BITS : positive := CODEWORDS * 7;
    constant TRAIN_BITS : positive := 64;
    constant SYNC_BITS : positive := 32;
    constant SYNC_WORD : std_logic_vector(31 downto 0) := x"1ACFFC1D";
    subtype payload_t is std_logic_vector(PAYLOAD_BITS-1 downto 0);
    subtype info_t is std_logic_vector(INFO_BITS-1 downto 0);
    subtype body_t is std_logic_vector(BODY_BITS-1 downto 0);
    subtype code_t is std_logic_vector(6 downto 0);
    subtype nibble_t is std_logic_vector(3 downto 0);
    subtype crc_t is unsigned(15 downto 0);
    subtype count_t is unsigned(31 downto 0);
    subtype sample_t is signed(7 downto 0);
    type sine_table_t is array (0 to 31) of integer range -127 to 127;
    constant SINE32 : sine_table_t :=
       (0,25,49,71,90,106,117,125,127,125,117,106,90,71,49,25,
        0,-25,-49,-71,-90,-106,-117,-125,-127,-125,-117,-106,-90,-71,-49,-25);
    function hamming_encode(d : nibble_t) return code_t;
    function hamming_syndrome(c : code_t) return unsigned;
    function hamming_decode(c : code_t) return nibble_t;
    function crc_step(crc : crc_t; b : std_logic) return crc_t;
    function prbs_next(v : unsigned(15 downto 0)) return unsigned;
    function payload_seed(seq : unsigned(15 downto 0)) return unsigned;
    function make_payload(seq : unsigned(15 downto 0)) return payload_t;
    function make_info(seq : unsigned(15 downto 0)) return info_t;
    function encode_info(info : info_t) return body_t;
    -- i counts transmitted bits, MSB first. Result indexes the original
    -- contiguous codeword stream, also MSB first.
    function interleave_source(i : natural; depth : positive) return natural;
    function interleave_body(b : body_t; depth : positive) return body_t;
    function bit_errors(a, b : std_logic_vector) return natural;
end package;

package body comm_stream_pkg is
    function hamming_encode(d : nibble_t) return code_t is
        variable c : code_t;
    begin
        c(0) := d(0) xor d(1) xor d(3);
        c(1) := d(0) xor d(2) xor d(3);
        c(2) := d(0);
        c(3) := d(1) xor d(2) xor d(3);
        c(4) := d(1); c(5) := d(2); c(6) := d(3);
        return c;
    end;
    function hamming_syndrome(c : code_t) return unsigned is
        variable s : unsigned(2 downto 0);
    begin
        s(0) := c(0) xor c(2) xor c(4) xor c(6);
        s(1) := c(1) xor c(2) xor c(5) xor c(6);
        s(2) := c(3) xor c(4) xor c(5) xor c(6);
        return s;
    end;
    function hamming_decode(c : code_t) return nibble_t is
        variable fixed : code_t := c;
        variable p : natural range 0 to 7;
    begin
        p := to_integer(hamming_syndrome(c));
        if p /= 0 then fixed(p-1) := not fixed(p-1); end if;
        return fixed(6) & fixed(5) & fixed(4) & fixed(2);
    end;
    -- CRC-16/CCITT-FALSE: poly 1021, init FFFF, MSB first,
    -- no reflection, xorout 0000. CRC covers sequence and payload.
    function crc_step(crc : crc_t; b : std_logic) return crc_t is
        variable c : crc_t := shift_left(crc, 1);
    begin
        if (crc(15) xor b) = '1' then c := c xor x"1021"; end if;
        return c;
    end;
    function prbs_next(v : unsigned(15 downto 0)) return unsigned is
    begin
        return v(14 downto 0) & (v(15) xor v(13) xor v(12) xor v(10));
    end;
    function payload_seed(seq : unsigned(15 downto 0)) return unsigned is
        variable v : unsigned(15 downto 0) := seq xor x"1D0F";
    begin
        if v = 0 then v := to_unsigned(1,16); end if;
        return v;
    end;
    function make_payload(seq : unsigned(15 downto 0)) return payload_t is
        variable p : payload_t;
        variable lfsr : unsigned(15 downto 0) := payload_seed(seq);
    begin
        for i in p'high downto 0 loop
            p(i) := lfsr(15); lfsr := prbs_next(lfsr);
        end loop;
        return p;
    end;
    function make_info(seq : unsigned(15 downto 0)) return info_t is
        variable info : info_t;
        variable crc : crc_t := x"FFFF";
    begin
        info := std_logic_vector(seq) & make_payload(seq) & x"0000";
        for i in INFO_BITS-1 downto 16 loop crc := crc_step(crc,info(i)); end loop;
        info(15 downto 0) := std_logic_vector(crc);
        return info;
    end;
    function encode_info(info : info_t) return body_t is
        variable b : body_t;
    begin
        for w in 0 to CODEWORDS-1 loop
            b(BODY_BITS-1-7*w downto BODY_BITS-7-7*w) :=
                hamming_encode(info(INFO_BITS-1-4*w downto INFO_BITS-4-4*w));
        end loop;
        return b;
    end;
    function interleave_source(i : natural; depth : positive) return natural is
    begin
        return (i/(7*depth))*(7*depth) + (i mod depth)*7 + (i mod (7*depth))/depth;
    end;
    function interleave_body(b : body_t; depth : positive) return body_t is
        variable result : body_t;
    begin
        for i in 0 to BODY_BITS-1 loop
            result(BODY_BITS-1-i) := b(BODY_BITS-1-interleave_source(i,depth));
        end loop;
        return result;
    end;
    function bit_errors(a,b : std_logic_vector) return natural is
        variable result : natural := 0;
        alias aa : std_logic_vector(a'length-1 downto 0) is a;
        alias bb : std_logic_vector(b'length-1 downto 0) is b;
    begin
        assert a'length = b'length report "bit_errors length mismatch" severity failure;
        for i in aa'range loop
            if aa(i) /= bb(i) then result := result + 1; end if;
        end loop;
        return result;
    end;
end package body;
