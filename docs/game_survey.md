# Game survey: what TMS34010 games ask of the chip

Part 0 of `PLAN_DROPIN.md` (kept on C: in the project folder). It orders the rest of the drop-in work by what
real games use, measured rather than guessed.

**What MAME is used for here.** MAME 0.282's drivers are read for *board facts* (clocks, which chips sit
around the 34010), and a MAME build with counters added to its TMS34010 device records *what each game's own code
asks for*: which opcodes run, which I/O registers are written with which values, which interrupts are taken, how
graphics instructions are set up. These are facts about the games' code. Nothing about how the chip does
anything is taken from MAME; that comes from TI's User's Guide (SPVU001A, 1988).

## 0.1 Board facts (from MAME 0.282 drivers, read for facts only)

"Video" means the 34010 programs the video timing (MAME drives the screen from the 34010's own HTOTAL/VTOTAL etc.
through `set_scanline_*_callback`). "SRT" means the driver connects the shift-register transfer callbacks
(`set_shiftreg_in/out_callback`), i.e. the game's VRAM is refreshed through the 34010's SRT cycles. "Host"
means another CPU talks to the 34010 through its host interface (`host_r`/`host_w`).

| Board / driver (MAME file) | Games surveyed | 34010 clock | 34010s | Host CPU on the host interface | Video | SRT | Halted at reset |
|---|---|---|---|---|---|---|---|
| Midway Z-unit (`midway/midyunit.cpp`, `zunit`) | NARC | 48 MHz | 1 | none | yes | yes | no |
| Midway Y-unit, "slow" (`midyunit.cpp`) | Trog, Smash TV, High Impact, Super High Impact | 40 MHz | 1 | none | yes | yes | no |
| Midway Y-unit, "fast" | Strike Force, Mortal Kombat (Y-unit, mkla4), Total Carnage | 48 MHz | 1 | none | yes | yes | no |
| Midway Y-unit, "faster" | Terminator 2 | 50 MHz | 1 | none | yes | yes | no |
| Midway T-unit (`midway/midtunit.cpp`) | Mortal Kombat (T-unit), MK II, Judge Dredd, NBA Jam, NBA Jam TE | 50 MHz | 1 | none | yes | yes | no |
| Midway W-unit (`midway/midwunit.cpp`) | MK3, UMK3, WWF WrestleMania, Open Ice, NBA Hangtime, Rampage World Tour | 50 MHz | 1 | none | yes | yes | no |
| Atari Hard Drivin' family (`atari/harddriv.cpp`) | Hard Drivin' (cockpit, compact), Race Drivin' (cockpit, compact), STUN Runner, Steel Talons, Hard Drivin's Airborne, Street Drivin' | GSP 48 MHz; MSP 50 MHz (boards that have one) | 1 or 2 | 68010 on both | GSP yes, MSP no | GSP yes | yes (both) |
| Gottlieb Exterminator (`gottlieb/exterm.cpp`) | Exterminator | 40 MHz | 2 | master: none; slave: the master 34010, through the slave's host interface | master yes | both | master no, slave yes |
| ICE (`ice/lethalj.cpp`) | Lethal Justice, Egg Venture, Ripper Ribbit, Chicken Farm, Crazzy Clownz | 40 MHz | 1 | none | yes | no | no |
| Cool Pool family (`misc/coolpool.cpp`) | Ameri Darts, Cool Pool, 9-Ball Shootout | 40 MHz | 1 (plus a TMS320 DSP) | none | yes | yes | no |
| Tickee family (`misc/tickee.cpp`) | Tickee Tickats, Ghost Hunter, Tut's Tomb, Mouse Attack, Mallet Madness; Rapid Fire | 40 MHz; Rapid Fire 50 MHz | 1 | none | yes | Rapid Fire only | no |
| Skimaxx (`misc/skimaxx.cpp`) | Skimaxx | 50 MHz | 1 | 68EC030 | yes | yes | no |
| Rare X the Ball (`rare/xtheball.cpp`) | X the Ball | 40 MHz | 1 | none | yes | yes | no |
| Micro3D (`misc/micro3d.cpp`) | F-15 Strike Eagle, BOTSS, Tank Battle | 40 MHz | 1 | 68000 | yes | no | no |
| JPM Impact video (`jpm/jpmimpct.cpp`) | Cluedo, Trivial Pursuit, Scrabble | 40 MHz | 1 | 68000 | yes | yes | yes |
| Art & Magic (`misc/artmagic.cpp`) | Ultimate Tennis, Cheese Chase, Stone Ball | 40 MHz | 1 | 68000 | yes | yes | yes |
| Inder video board (`shared/inder_vid.cpp`) | Mega Phoenix, Hammer Boy (`misc/megaphx.cpp`), Little Robin (`tch/littlerb.cpp`) | 40 MHz | 1 | 68000 | yes | yes | yes |

Not surveyed:
- **TMS34020 boards:** Midway X-unit (Revolution X), Rare Battletoads, Atari Metal Maniax and Atronic. The 34020
  is a different chip (guide appendix C); out of scope.
- **Sets MAME marks not working:** Pot o' Gold, Skeet Shot / Pop Shot, Frantic Fred and Shooting Star. A survey of
  a game that doesn't run would measure nothing.
- **Bee-Zerk (VLC) and the Tektronix XP33x terminal:** the first is not working; the second is not a game.

Clocks: INCLK is divided internally by 8 to make the local clocks LCLK1/LCLK2 (guide appendix A, p. A-40), so
40, 48 and 50 MHz boards run 5, 6 and 6.25 MHz local clocks. Our core's `CLKS_PER_STATE=8` assumes the FPGA clock
equals INCLK.

## 0.2 What the games' code asks for

**How it was measured.** A private build of MAME 0.282 with counters added to its TMS34010 device only (how often
each opcode word executes; for every pixel-writing instruction the CONTROL, PSIZE and DPYCTL values it ran with;
every I/O register write with its value; every I/O register read; every interrupt taken; every host access). The
counters record what the game's code asks the chip for; MAME's own emulation of the answers is not used for
anything here. Each set ran headless for about 5 emulated minutes: 90 s of attract mode, then a coin, start and
random player inputs every 8 frames, with another coin and start every 50 s (and a second player on alternate
rounds). Scripts: `tools/dropin/survey/` (`play.lua`, `run1.sh`, `analyze.py`, `matrix.py`, `matrix_doc.py`).

**Coverage.** 57 34010s from 56 sets: every set in 0.1, the Exterminator's two 34010s, 7 Atari GSPs (Hard Drivin',
Race Drivin' cockpit and compact, STUN Runner, Steel Talons, Hard Drivin's Airborne, Street Drivin'). Gaps:
- **Hard Drivin' compact (`harddrivc`):** the 68010 loads the GSP but never clears HLT in MAME within 5 minutes, so
  its GSP ran nothing. Race Drivin' compact (same board family) is covered.
- **Atari MSP:** none of the Atari configurations above started an MSP in MAME. Not measured.
- **BOTSS** stopped at 265 s on an Am29000 error in MAME's 3D board (not the 34010); 265 s of data kept.
- 5 minutes of random play does not reach every part of a game (late levels, service menus, high-score entry).
  Anything a game uses only there is missing. A feature counted as used is certainly used; one not counted is only
  "not seen".

The full table is `game_survey_matrix.md` (generated). The findings that set the order of the work:

**Instructions.** 134 of the 139 instruction forms MAME distinguishes were executed by at least one game. Never
executed: EMU, NEGB, SLA Rs, and the two illegal-opcode classes (no game ran an illegal opcode). Rare but used:
SUBB (Cool Pool family), REV (JPM), SRA Rs (4), MODS/MODU (9 each), TRAP (13).

**Graphics.** Every pixel-writing form is used somewhere:

| Form | 34010s | Families |
|---|---|---|
| PIXBLT B,XY | 39 | Midway Z/Y/T/W, Atari, Exterminator, Cool Pool, X the Ball, Micro3D, JPM |
| PIXT *Rs,Rd | 36 | most |
| FILL XY | 33 | most |
| FILL L, PIXBLT L,XY | 21 each | |
| PIXT Rs,*Rd.XY | 19 | |
| PIXBLT L,L | 17 | Tickee, Cool Pool, Art & Magic, JPM, Skimaxx, ... |
| LINE | 10 | Atari GSP (all 7), Micro3D, Cool Pool |
| DRAV | 10 | Midway Y-unit (6), Cool Pool, Exterminator, Atari |
| PIXBLT XY,L | 4 | Micro3D, X the Ball |
| PIXT *Rs.XY,*Rd.XY / *Rs.XY,Rd | 3 / 3 | Atari, Cool Pool, X the Ball |
| PIXBLT B,L, PIXBLT XY,XY, PIXT *Rs,*Rd | 1 each | JPM; Cool Pool; Cool Pool |

The ICE family (Lethal Justice, Egg Venture, Ripper Ribbit, Chicken Farm, Crazzy Clownz) runs no graphics
instruction at all.

**Pixel processing.** Replace almost everywhere; MAX (NARC, X the Ball), MIN (Cool Pool family), NOT S AND D
(Exterminator). No other pixel operation appears. **No game sets a plane mask** (PMASK stays 0 in all 57).
Transparency is used by 48. Pixel sizes 8 (46 CPUs), 16 (14), 2 (5, Atari), 1 (2, Atari), 4 (2).

**Windows.** W=3 clipping in 28 34010s (every Atari GSP, Tickee, Cool Pool, JPM, Art & Magic, Inder, ...);
W=1 in 5 (Cool Pool, JPM); W=2 never.

**Interrupts.** Display interrupt in 53; INT1 in 25 (Midway, ICE, Tickee); INT2 in 7; host interrupt (HIE) enabled in
5 (Micro3D, JPM); NMI with NMIM=1 (no context saved) in 3 (Exterminator's slave, JPM). Window-violation interrupts
never.

**Host interface.** 21 34010s sit behind a host (Atari GSPs, Exterminator slave, Skimaxx, Micro3D, JPM, Art & Magic,
Inder). Hosts use HSTADR/HSTDATA with INCW (20) and INCR (16), HLT (17), cache flush CF (14), LBL (10: Atari, Inder),
INTIN/INTOUT (5: Art & Magic and Inder, whose 34010s never enable HIE, so INTIN is not taken as an interrupt there) and NMI (3: Exterminator, JPM).

**Video.** All 34010s program the video timing. SRT (VRAM shift-register transfers) in 44. External sync (DXV=0) in
4: the Exterminator's slave and the 3 JPM boards. Interlace (NIL=0) in the 3 JPM boards. HSD=1 on Art & Magic. CAS-
before-RAS refresh (RM=1) in 40, both refresh rates used. One game turns the instruction cache off (CD=1, Tickee).

**Edge cases from the open questions (second pass).** A second pass of all sets recorded, for every pixel
instruction, whether the linear destination or source address is a multiple of the pixel size and whether the row
is wider than 32 pixels:
- **C17** (accurate mode hangs on a linear FILL/PIXBLT destination that is not pixel-aligned): **no game** does it.
- **C15** (Table 13-12, expand rows wider than 32 pixels): the Atari GSPs do it (Race Drivin' cockpit and compact,
  Street Drivin'; PIXBLT B,XY at 1 and 2 bits per pixel). A real timing question for those boards.
- **Linear source not pixel-aligned:** the JPM boards (Cluedo, Scrabble) run PIXBLT L,XY at PSIZE 8 from odd bit
  offsets. Added to the system-level pixel matrix (246 cases, every source bit offset at PSIZE 4/8/16): identical
  in both modes (the two engines agree; there is no independent reference for these cases).

## 0.3 The order this gives

1. **Everything common is already in the evidence:** the instruction set, PIXBLT/FILL/PIXT/DRAV with Replace and
   transparency at 8 and 16 bits, display and external interrupts, SRT. (Timing bench, the new system-level pixel
   matrix, upstream's benches.)
2. **The host interface** is used by 21 of 57: the system-level host bench (`sim/dropin/tb_host_sys.sv`) now covers
   load/readback, HLT, indirect accesses while running, NMI (NMIM 0 and 1), INTIN, INTOUT/HINT, CF and LBL=1 in both
   modes. Not covered: 8-bit (byte-wide) hosts, which no surveyed board has.
3. **Window clipping W=3 and LINE** (Atari, the heaviest graphics users): functional evidence is upstream's, plus
   negative coordinates against the guide (`tb_negxy_sys`; upstream clipped them wrongly, fixed 2026-10-09); the
   accurate model's W=3 and LINE timing items (C10, C14-C16 in `cycle_accuracy.md`) come next.
4. **Pixel sizes 1 and 2** (Atari) and the MIN/MAX/NOT S AND D operations: covered by the system-level matrix in both
   modes; timing at sizes 1/2 to check.
5. **External sync and interlace** (Exterminator slave, JPM): video logic is the same in both modes; upstream's
   `tb_video_external_sync` and `tb_video_interlace` are the evidence. The two-GSP arrangement (guide 9.9.1, the
   Exterminator) is checked at video-timing level by `tb_two_gsp_sync` (dropin_audit.md), with the game's own
   register values (exactly Table 9-1); horizontal blanking ending less than 3 clocks into the line is not supported
   there, and no game does it. At system level (`tb_two_gsp_sys`: two full systems, each CPU programming its own
   registers with the game's values) BLANK also switches in unison, in both modes.
6. **Out of scope by measurement:** plane masking (no game uses it; it is implemented and in the matrix anyway), W=2,
   window-violation interrupts, EMU, NEGB/SLA Rs (implemented and tested; just unused), C17 (no game makes a
   misaligned linear destination), C16 (concerns plane masking, which no game uses).
7. **B2 (`GRAPHICS_INSTR=0`)** would only fit boards that run no graphics instruction: the ICE family, and an Atari
   MSP if one is ever built. Worth doing only if someone builds those; it is not needed for the others.
