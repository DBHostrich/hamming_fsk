library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.comm_stream_pkg.all;

-- Sample-only receiver: no TX start, symbol clock, frame counter or bit
-- boundary enters this entity. Every possible sample phase searches the
-- sync word. Noncoherent two-frequency correlation tolerates carrier phase.
entity comm_sample_rx is
    generic (SAMPLES_PER_SYMBOL : positive := 128;
             SYNC_MAX_ERRORS : natural := 0; MIN_ENERGY : positive := 64);
    port (clk, reset, sample_ce : in std_logic; sample_in : in sample_t;
          frame_start, bit_valid, bit_out, locked : out std_logic;
          timing_phase : out unsigned(7 downto 0));
end;

architecture rtl of comm_sample_rx is
    subtype product_t is signed(15 downto 0);
    subtype sum_t is signed(23 downto 0);
    subtype energy_t is unsigned(32 downto 0);
    type product_ram_t is array(0 to SAMPLES_PER_SYMBOL-1) of product_t;
    type history_t is array(0 to SAMPLES_PER_SYMBOL-1) of std_logic_vector(31 downto 0);
    signal p0c,p0s,p1c,p1s : product_ram_t := (others=>(others=>'0'));
    signal s0c,s0s,s1c,s1s : sum_t := (others=>'0');
    signal histories : history_t := (others=>(others=>'0'));
    signal write_pos : natural range 0 to SAMPLES_PER_SYMBOL-1 := 0;
    signal reference_phase : natural range 0 to 31 := 0;
    signal filled : natural range 0 to SAMPLES_PER_SYMBOL := 0;
    signal acquiring : std_logic := '0';
    signal scan_count : natural range 0 to SAMPLES_PER_SYMBOL-1 := 0;
    signal best_phase, selected_phase : natural range 0 to SAMPLES_PER_SYMBOL-1 := 0;
    signal best_score : energy_t := (others=>'0');
    signal is_locked : std_logic := '0';
    signal body_index : natural range 0 to BODY_BITS-1 := 0;
    function energy(c,s : sum_t) return energy_t is
        variable cc,ss : signed(15 downto 0);
        variable square_c,square_s : signed(31 downto 0);
    begin
        -- Maximum full-scale sum / 256 fits safely in signed 16 bits
        -- for the supported 128/256-sample windows.
        cc:=resize(shift_right(c,8),16); ss:=resize(shift_right(s,8),16);
        square_c:=cc*cc; square_s:=ss*ss;
        return resize(unsigned(square_c),33)+resize(unsigned(square_s),33);
    end;
begin
    assert SAMPLES_PER_SYMBOL>=32 and SAMPLES_PER_SYMBOL<=256 and
           SAMPLES_PER_SYMBOL mod 32=0 report "Invalid samples per symbol" severity failure;
    assert SYNC_MAX_ERRORS<=4 report "Excessive sync tolerance" severity failure;
    locked<=is_locked;
    timing_phase<=to_unsigned(selected_phase,8);
    process(clk)
        variable a0c,a0s,a1c,a1s : product_t;
        variable n0c,n0s,n1c,n1s : sum_t;
        variable e0,e1,score,chosen_score : energy_t;
        variable decision : std_logic;
        variable history : std_logic_vector(31 downto 0);
        variable match : boolean;
        variable chosen_phase : natural range 0 to SAMPLES_PER_SYMBOL-1;
    begin
        if rising_edge(clk) then
            frame_start<='0'; bit_valid<='0';
            if reset='1' then
                p0c<=(others=>(others=>'0')); p0s<=(others=>(others=>'0'));
                p1c<=(others=>(others=>'0')); p1s<=(others=>(others=>'0'));
                s0c<=(others=>'0'); s0s<=(others=>'0');
                s1c<=(others=>'0'); s1s<=(others=>'0');
                histories<=(others=>(others=>'0')); write_pos<=0; reference_phase<=0;
                filled<=0; acquiring<='0'; scan_count<=0; best_phase<=0;
                selected_phase<=0; best_score<=(others=>'0');
                is_locked<='0'; body_index<=0; bit_out<='0';
            elsif sample_ce='1' then
                a0c:=sample_in*to_signed(SINE32((reference_phase+8) mod 32),8);
                a0s:=sample_in*to_signed(SINE32(reference_phase),8);
                a1c:=sample_in*to_signed(SINE32((2*reference_phase+8) mod 32),8);
                a1s:=sample_in*to_signed(SINE32((2*reference_phase) mod 32),8);
                n0c:=s0c+resize(a0c,24)-resize(p0c(write_pos),24);
                n0s:=s0s+resize(a0s,24)-resize(p0s(write_pos),24);
                n1c:=s1c+resize(a1c,24)-resize(p1c(write_pos),24);
                n1s:=s1s+resize(a1s,24)-resize(p1s(write_pos),24);
                p0c(write_pos)<=a0c; p0s(write_pos)<=a0s;
                p1c(write_pos)<=a1c; p1s(write_pos)<=a1s;
                s0c<=n0c; s0s<=n0s; s1c<=n1c; s1s<=n1s;
                e0:=energy(n0c,n0s); e1:=energy(n1c,n1s);
                if e1>e0 then decision:='1'; score:=e1-e0;
                else decision:='0'; score:=e0-e1; end if;
                reference_phase<=(reference_phase+1) mod 32;
                if write_pos=SAMPLES_PER_SYMBOL-1 then write_pos<=0;
                else write_pos<=write_pos+1; end if;
                if filled<SAMPLES_PER_SYMBOL then filled<=filled+1; end if;

                if filled>=SAMPLES_PER_SYMBOL-1 then
                    if is_locked='1' then
                        if write_pos=selected_phase then
                            bit_out<=decision; bit_valid<='1';
                            if body_index=BODY_BITS-1 then
                                is_locked<='0'; body_index<=0;
                                histories<=(others=>(others=>'0'));
                            else body_index<=body_index+1; end if;
                        end if;
                    else
                        history:=histories(write_pos)(30 downto 0)&decision;
                        histories(write_pos)<=history;
                        match:=bit_errors(history,SYNC_WORD)<=SYNC_MAX_ERRORS and
                               (e0+e1)>=to_unsigned(MIN_ENERGY,33);
                        if acquiring='0' then
                            if match then
                                acquiring<='1'; scan_count<=0;
                                best_score<=score; best_phase<=write_pos;
                            end if;
                        else
                            chosen_phase:=best_phase; chosen_score:=best_score;
                            -- Search one symbol's worth of candidates. Strict
                            -- comparison keeps the earliest equal-quality phase.
                            if match and score>best_score then
                                chosen_phase:=write_pos; chosen_score:=score;
                            end if;
                            best_phase<=chosen_phase; best_score<=chosen_score;
                            if scan_count=SAMPLES_PER_SYMBOL-2 then
                                selected_phase<=chosen_phase; is_locked<='1';
                                acquiring<='0'; body_index<=0; frame_start<='1';
                            else scan_count<=scan_count+1; end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end rtl;
