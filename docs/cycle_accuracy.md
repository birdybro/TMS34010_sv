# Cycle accuracy (accuracy branch)

Goal: with `CYCLE_ACCURATE=1` and `CLKS_PER_STATE=N` (N >= 8), every instruction takes the number of machine
states the TMS34010 User's Guide gives, times N core clocks.

**Edition.** The authority is the June 1988 revision, SPVU001A (`third_party/TMS34010_Info/docs/ti-official/
1988_TI_TMS34010_Users_Guide.pdf`); page numbers below are its pages. The January 1986 first edition (SPVU001)
differs in places: MMFM (3+8n with Rp not aligned), MPYS/MPYU (fixed 20/21), EMU (6), JRcc long not taken (2),
Table 13-1 MOVE @Address,Rd G (19), Table 13-2 Rs,*Rd(offset) and Rs,@Address cache off (7..15), REFCNT
(counts up). The 1988 Section 12 pages repeat some figures that its Section 13 tables changed (MOVE Rs,*Rd(offset)
16-bit 3+(1),7 on 12-132 vs 3+(1),9 in Table 13-2); the bench follows the tables, the figures TI revised. With the defaults
(`CYCLE_ACCURATE=0`, `CLKS_PER_STATE=1`) the design behaves as upstream's Task 0174 sign-off except for five
fixes that apply in both modes: JRP tests condition 0001 "P" (N=0 and Z=0), BTST K takes the one's complement
of the encoded K, no interrupt is taken while an opcode fetch is outstanding, window checks treat X and Y as
signed (with a W=3 clip of an array left of X = 0 starting at the clipped corner), and LINE with W=1 draws no
pixels (C10).

The timing is not looked up. It comes from modelled parts of the chip, each from the guide:

| Part | Guide | Model |
|---|---|---|
| Machine state | 13.1; 2-x pin timing: one state = one local clock | `CLKS_PER_STATE` core clocks |
| Local memory cycle | 5.4.7 ("eight machine cycles ... to load four words"); 13.2 tables | each word cycle occupies the bus for 2 states |
| Wait states | LRDY pin description, 11.4.10 | a late `cycle_ack_i` adds whole states |
| Hidden states | 13.1.1 | the memory controller takes a write and finishes it while the CPU goes on; the next instruction that needs the bus waits |
| Instruction cache | 5.4.1-5.4.6 | 4 segments x 8 subsegments x 4 words, SSA registers, P flags, LRU stack, CD/CF |
| CPU states | Section 12 "Machine States", 13.2 tables | each instruction's microcode length in states (see below) |

## Minimum clock ratio

The core spends a few clocks per instruction on decode and the fabric a few more registering a request; these
are kept inside the instruction's states. That fits from 8 core clocks per state (48 MHz for a 6 MHz local
clock); below that, some instructions take longer than the guide says (at 7, MOVE stores, MOVB stores, short
JRUC and TRAP). The core stops simulation with an error if `CYCLE_ACCURATE=1` and `CLKS_PER_STATE < 8`.

## How the guide's numbers decompose

Checked across Section 12 and Tables 13-1/13-2/13-4:

- **Cache-off = cache-hit + hidden + 3 per instruction word.** For example ADD 1,4; ADDI IW 2,8; MOVE Rs,*Rd
  A 1+(1),5; CALL Rs 3+(3),9; PUSHST 2+(3),8; MOVE Rs,@Address A 3+(1),13; MMFM 3+4n+(2),11+4n. So an instruction fetch from memory costs 3 states (a 2-state
  bus cycle and 1 state), a fetch from the cache costs nothing extra, and in the cache-off case the next
  opcode fetch waits for the hidden writes. Exceptions: see "Where the guide disagrees with itself".
- **Cache miss**: 8 states to load the 4-word subsegment plus 1 (5.4.7).
- **Writes**: hidden = 2 x (word cycles) - 1. A, 1 cycle: (1); B and C, 2 cycles: (3); D and E, 3: (5); F, 4:
  (7); G, 5: (9) (Table 13-2; B is a read-modify-write of one word, Section 4/13.2.1). So the write's first
  cycle starts in the instruction's last CPU state. Figure 5-9 shows the same for PIXT.
- **Reads**: the cache-hit figure = CPU states + 2 per word read. MOVE *Rs,Rd: 1 + 2 (A, B), 1 + 4 (C-F),
  1 + 6 (G); -*Rs: 2 + ...; *Rs(Disp): 3 + ...; @Address: 3 + ... (Table 13-1). Figure 5-9 shows the read in
  the instruction's last two states.

So each instruction form has a fixed number of CPU states that doesn't depend on field alignment; the
alignment only changes how many word cycles the memory controller runs.

## How the model is built

- **State grid.** One free-running phase counter; a state ends every `CLKS_PER_STATE` clocks.
- **CPU states.** A per-instruction counter counts the states in which the CPU was not held. The CPU is
  held in a state if, at any clock of it, it was waiting for memory (a read or fetch outstanding, or a
  write waiting for the controller to take it). The next opcode is fetched at the start of the first
  state after the count reaches the instruction's CPU states plus one for every instruction word that
  had to come from memory instead of the cache (13.1 cache-off figures, 5.4.7 miss penalty).
- **Bus timeline.** The bus is a timeline of whole states. A CPU cycle is timed from the start of the
  state in which the core asked for it (or from when the bus became free, if later), not from when the
  arbiter presents it outside. On the chip, decode overlaps the previous instruction and the cycle starts
  at the state boundary; this core instead spends a few clocks decoding and the fabric a few more
  registering the request, and those clocks are kept inside the cycle's two states. The external
  `cycle_ack_i` is the ready input, sampled in the last clock of each state from the cycle's second state
  on: if it hasn't come, the cycle grows by one whole state (a wait state).
- **I/O registers.** I/O register cycles go out on the cycle bus as their own kinds and wait for
  `cycle_ack_i` like any other cycle. On the chip LRDY is ignored for them, so the bridge should ack I/O
  kinds at once.
- **Same-clock answers.** A cache hit and a posted write that the controller can take are answered in
  the same clock, so the core's fixed work per instruction fits inside one state.
- **Plane masking and transparency** are applied by the memory controller inside the write (C6).
- **Windowed LINE** pixels that aren't drawn make no access either (C10).
- **Windowed XY PIXT stores.** Upstream reads the destination and writes the old value back when the
  pixel isn't drawn. With `CYCLE_ACCURATE=1` the store decides after reading WSTART/WEND, as DRAV does:
  no access when the pixel isn't drawn, a plain store when it is (12-216).

## FILL (word engine)

With `CYCLE_ACCURATE=1` FILL works a word at a time (13.3.2.2): each step writes the pixels from the current
address to the next word boundary or the end of the row. An edge word is a partial field, so the field
sequencer makes it a read-modify-write; centre words are plain word writes. Pixel processing reads the word
and applies the operation to all its pixels at once (`ppop_word`); plane masking and transparency are kept
per pixel by the memory controller (C6). Upstream's pixel engine still runs with `CYCLE_ACCURATE=0`; both give
the same registers and memory in every bench run, including runs interrupted in the middle of the FILL.

Timing comes from the same parts as everything else:
- setup (Table 13-5): FILL L 4, FILL XY 6; W=3 preclipping 9 (array fits), 16 (start corner moves),
  12 (far corner moves), 20 (both). The first access starts after the setup states.
- the words: the bus model (2 states a word write, 4 a read-modify-write, a read before the write for pixel
  processing, one or two more CPU states for ADDS/SUB/MAX/MIN or SUBS: Table 13-7's G).
- per row and at the end: after a row's last write has finished, the CPU spends a few states on the row;
  after the last row, a few more. These are Table 13-6's row and end constants less the edge
  read-modify-writes the bus already times, by row class (N = 1, 2, 3+ words) and edge alignment:

  | Row | states per row A/B/C/D | end A/B/C/D |
  |---|---|---|
  | short (N=1) | 1/0/0/0 | 2/2/1/1 |
  | medium (N=2) | 2/1/1/0 | 2/2/2/1 |
  | long (N>=3) | 1/0/1/0 | 2/5/2/1 |

  With these, the bus model reproduces every entry of Table 13-6 for every G of Table 13-7, including the
  13.3.2.6 alignment/graphics adjustment, except one: short rows with alignment D and plane masking or
  transparency, where 13.3.2.6 subtracts 4 per row although a one-word row has only one read-modify-write
  (note `short-d-adjust`).

## PIXBLT (word engine)

With `CYCLE_ACCURATE=1` every PIXBLT form moves a destination word at a time (13.4.2.2, 13.5.2.2); upstream's
pixel engine runs with `CYCLE_ACCURATE=0`, and both give the same registers and memory in every bench run
(also when interrupted mid-transfer), except where source and destination overlap: the word engine reads
each source word once, before the destination words that need it are written, as the chip does
(13.4.2.4-5; choose PBH/PBV so a move doesn't overwrite source it hasn't read yet).

- **Full color (L,L / L,XY / XY,L / XY,XY):** steps run in the PBH direction to the next destination word
  boundary or the row end. The source is read in sequence into a two-word buffer, one word per
  destination word and one more for a row's first destination word when it needs two (D < S, 13.4.2.4),
  which is how Table 13-9 times every row. Setup (Table 13-8): L,L 7, XY,L and L,XY 9, XY,XY 12; W=3
  preclip with an XY destination +3 (fits), +10 (start), +6 (dimension), +14 (both); corner adjust for the
  XY forms +1 (PBH), +2 (PBV), +4 (both). Row and end states after each row's last write:

  | PBH | row | states per row | end |
  |---|---|---|---|
  | 0 | short | 2 (0 with D<S) | 5 if both edges aligned, else 3 |
  | 0 | medium | 2 | 5 if the trailing edge is aligned, else 3; one less with D<S |
  | 0 | long | 0 | as medium |
  | 1 | short | 1 if both edges aligned and D>=S, else 0 | 8 if both edges aligned, else 7 |
  | 1 | medium | 2, one less with D<S and the trailing edge partial | 4 if trailing edge aligned, else 3; one more with D<S |
  | 1 | long | 1, one less with D<S and the trailing edge partial | as medium |

- **Expand (B,L / B,XY):** the binary source is read in segments of up to 32 bits (one field read: R source
  words, 13.5.2.4); each step writes COLOR1/COLOR0 per source bit at the destination position. After each
  segment read the CPU spends 3 states (1 when the segment's first destination write is not a whole word);
  3 at the end. Setup (Table 13-11): B,L 4, B,XY 6; W=3 9/17/12/21.

## Bench

`scripts/accuracy.sh` (cases in `tools/accuracy/cases.py`, bench `sim/accuracy/tb_accuracy.sv`, report
`tools/accuracy/report.py`). An instruction is timed from the clock its opcode fetch completes to the clock
the next opcode fetch completes, which is how the guide counts (see the first bullet above). Its hidden states
are timed from the start of the state in which the next opcode fetch completed to the end of its last bus
cycle (within 11 states; every measured instruction is followed by at least 11 NOPs from the cache).

Every expectation is the figure printed in the guide (Table 13-4 read from the page image). Where the model
is known to give something else, the case carries a note naming an entry of the table below; the report
counts those as "differs (noted)", separately from matches and from unexplained differences.

## Where the guide disagrees with itself

The model follows the guide's general rules. These printed figures don't fit them; the bench reports them as
noted differences rather than the model being bent to them. Note keys are the ones in `cases.py`.

| Note | Guide figures | Says | General rule gives | Comment |
|---|---|---|---|---|
| jump-ext-off | JRcc long (12-97), JAcc (12-93), cache off | 6/7, 6/7 | 9/10, 12/13 | +3 counted for the opcode only, not the displacement / address words |
| store-off-a, store-off-f | MOVE Rs,*Rd(offset) A and F (T13-2), cache off | 9, 13 | 10, 16 | the B-E and G entries of the row, and the whole Rs,@Address row, follow the rule |
| movb-store-ext | MOVB Rs,*Rd(offset), Rs,@Address (T13-2), cache off | 7, 13 | 12-19 | the MOVB page 12-116 says 3+(3),9 for the offset form |
| movb-abs-b | MOVB Rs,@Address alignment B (T13-2, 12-117), cache hit | 1+(3) | 3+(3) | every other absolute/offset store has 3 CPU states |
| m2m-ext-off | Table 13-4 indices 6-9 of the *Rs(offset), @SAddr forms, cache off | e.g. 7+(3),13 | 16 | 3 lower (4 in column 8); the other columns of the same rows follow the rule |
| m2m-predec-8 | Table 13-4 -*Rs,-*Rd index 8, cache off | 6+(7),15 | 16 | the other forms' column 8 follow the rule |
| m2m-col12 | Table 13-4 index 12 (G to F), cache hit | 5..9 | 7..11 | the cache-off figures fit the rule with hit + 2 (the model) |
| movb-m2m | Table 13-4 MOVB *Rs(offset),*Rd(offset) and @S,@D, indices 2, 5, 8 | e.g. 5+(3),7; 6+(3),12 | 17, 27 | several entries are smaller than the hit figure plus the instruction words (12-121 says 5+(3),9) |
| pixt-off-row | PIXT Rs,*Rd PSIZE < 16 (12-214), cache off, ADD/SUB/SUBS/MIN-MAX | 11, 12, 11, 10 | 10, 11, 12, 11 | the PSIZE 16 row and every other form follow the rule; this row looks shuffled |
| drav-add | DRAV ADD, PSIZE < 16 (12-68) | 7+(3),13 | 6+(3),12 | every other ADD entry (and DRAV ADD at PSIZE 16) is the Boolean figure |
| mmtm-nonaligned | MMTM Rp not aligned (12-112) | 2+10n+(8), 10(n+1) | the two disagree by 6 | the model gives the cache-off figure (which Table 8-5 repeats) |
| mmfm-hidden | MMFM (12-110) | (2) aligned, (4) not | - | bus states after the last read; the cache-off figures count them. Not modelled: the guide doesn't say what the bus does then |
| fig-5-9 | Figure 5-9 (5-26) loop | 12 states | 11 (sum of the Section 12 figures) | |
| short-d-adjust | 13.3.2.6 / 13.4.2.7 / 13.5.2.7 adjustment for a one-word row with alignment D (FILL, PIXBLT) | -4 per row | -2 | only one word is read-modify-written |
| pblt-misprint | Table 13-9 PBH=0 long rows: D>=S D "[2+(4+G)N]L+3"; D<S per word "(2G)N" | | [4+(2+G)N]L+3; (2+G)N | every other entry has (2+G)N per word; the model gives the corrected figures exactly |
| pblt-short-ds | Table 13-9 PBH=1 short rows with D<S | same as D>=S | 1 or 2 more | the row's one destination word needs two source words; the D<S line repeats the D>=S one |
| expand-long | Table 13-12 long rows (alignments A, D) | e.g. [(3+2R+2GP)S + 2V + NG]L+3 | the 32-pixel segment model of 13.5.2.3 | "NG" counts every destination word again on top of 2GP per set; B and C aren't given; S is defined oddly |

Data dependences the guide gives and the model implements: taken / not taken (JRcc, JAcc, DSJ*, DSJS), Rd
even/odd, early exit on overflow and the >80000000 result (DIVS, DIVU, MODS, MODU), FS1 and the sign of Rs
(MPYS, MPYU), SETF F=1, MOVE sign
extension (13-1 note 1), pixel processing operation (PIXT, DRAV), window violation (PIXT XY, DRAV, LINE), registers
moved and pointer alignment (MMTM, MMFM), SP alignment (CALL*, RETS, PUSHST, POPST, TRAP, RETI, interrupt
entry), LINE pixels drawn, and the G-to-G memory-to-memory move (+2 states in every form of Table 13-4).

## Assumptions (TODO/spec-uncertain)

- C1: when a data read has to wait for hidden writes, the guide doesn't say whether the instruction's
  CPU state comes before or after the wait. Assumed: CPU states that come before the read in the
  instruction's microcode run in parallel with the wait.
- C2: a cache segment with no P flag set does not match (SSA contents after reset are not specified).
- C3: after reset or a flush the LRU stack holds segment 0 on top and 3 at the bottom ("numerical order").
- C4: a cache fill reads the subsegment's four words in ascending order.
- C5: where a write starts inside an instruction is worked out from the guide's hidden states
  (hidden = start state + bus states - 1 - CPU states). PUSHST starts its write a state earlier with SP not
  aligned (2+(3) vs 2+(8)). Interrupt entry takes 16 / 28 states (Table 8-4 note 3), TRAP 16 / 30 (12-254);
  checked with the bench's +INTAT on a NOP stream: 17 / 29 states from the last NOP's opcode fetch to the
  handler's (1 + 16, 1 + 28).
- C5a: LINT1/LINT2 recognition (8.3: sampled at each high-to-low transition of LCLK1, X1P/X2P change one to two
  states after the pin). With `CYCLE_ACCURATE=1` and more than one clock per state the synchronised pins go
  through two stages clocked once per state (`tms34010_io_regs` `g_lint_state`): the first takes the pin as it
  was at LCLK1's fall (half way through the state; the input synchroniser's 2 clocks are allowed for), the
  second passes it on in the clock before the next fall. X1P/X2P therefore change only in the clock where LCLK1
  falls, 8 to 15 clocks after the pin, and every pin edge between two falls gives the same result
  (`sim/tb/tb_lint_state.sv`). Upstream mode samples every clock, as before. The other interrupt sources are
  internal and need no sampling.
- C6: plane masking and transparency (13.3.2.5, Table 13-7): the memory controller applies them inside the
  write. With `CYCLE_ACCURATE=1` a PIXT, DRAV or LINE write carries the pixel bits to keep (`mem_keep`: the
  plane-masked bits, or the whole pixel when it is transparent) and a read-modify-write flag (`mem_rmw`: plane
  masking or transparency enabled, whatever the pixel values, as Table 13-7 times it); the field sequencer
  reads, merges and writes each word. The CPU reads the destination only for a pixel processing operation.
  At PSIZE 16 the guide prints no figure with T or PMASK; the bench expects the write's one cycle to become a
  read-modify-write (hidden (1) -> (3)). FILL and PIXBLT use the same mechanism per word.
- C7: I/O register writes are posted (6.2). The register takes its new value when the memory controller
  accepts the write, up to a few states before the bus cycle ends; 6.2 tells software not to rely on that
  window, and a later read of the register waits for the queued write.
- C8: DIVS/MODS "41,44 if result = 80000000h" (12-63, 12-113) is taken as a quotient magnitude of 2^31 (the
  case the sign correction has to handle). For MODS the remainder can't be 80000000h.
- C9: PIXT *Rs.XY,*Rd.XY gives no W=1 figure (12-225); taken as the W=2 one.
- C10: LINE window checking, Table 12-10 (12-102): W=1 5q+5, W=2 (3+P)E (+5 on a violation), W=3 (3+P)E+5q,
  q = pixels calculated but not written. Read as: an undrawn pixel takes 5 states, so does the violating
  pixel (W=1, W=2), and a W=1 line that never violates takes 5 more at its end (the table's "+5"). With
  `CYCLE_ACCURATE=1` an undrawn pixel makes no access (upstream reads and writes back every pixel of a
  windowed line). Behaviour fix in both modes: W=1 draws no pixels ("calculates points but no pixels are
  actually drawn", 12-101; 7.10.1); upstream drew the pixels outside the window (tb_line_abort updated).
- C11: MPYS/MPYU "5 + FS1/2" for an odd FS1 is taken as rounding up (one step per two bits); "Rs negative"
  for MPYU as the MSB of Rs's FS1-bit field.
- C12: FILL setup with W=1 or W=2, or with W=3 and the array wholly outside the window: Table 13-5 gives no
  figure ("-"); the model uses 9 (the "array fits" figure).
- C13: PIXBLT setup with W=1 or W=2, or W=3 with the array wholly outside the window: Table 13-8 / 13-11 give
  no figure; the model uses the "array fits" figure.
- C14: PIXBLT D>=S / D<S is decided per row by whether the first destination word written (in the PBH
  direction) needs two source words, which is 13.4.2.4's definition for PBH=0; the guide doesn't say how it
  applies with PBH=1.
- C15: Table 13-12 long expand rows (more than 32 source pixels): the model follows the text (32-pixel
  segments). Under the most self-consistent reading of the table (NG read as YG, "even number of sets" as "DX a
  multiple of 32") the model is 3 states per row more for alignment A, 3 or 5 for B, and matches no reading for
  C and D (REVIEW_2.md point 1).
- C16: expand colours are plane-masked before pixel processing, as upstream does (both modes); 7.6 may intend
  the mask to apply only to the write. It matters only for arithmetic pixel operations.
- C17 (known limitation): with `CYCLE_ACCURATE=1`, a linear FILL or PIXBLT whose destination address is not a
  multiple of the pixel size makes a step of 0 pixels and never finishes the row (the CPU hangs; REVIEW_3.md).
  The guide requires pixel-aligned pixel addresses, so this is out-of-spec input; `CYCLE_ACCURATE=0` steps one
  pixel at a time and finishes. A fix would keep the step at least 1 pixel and needs checking against upstream
  on misaligned cases.
