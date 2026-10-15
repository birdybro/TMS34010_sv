# A1: the whole chip, audited

Phase A1 of `PLAN_DROPIN.md`: for every part of TI's 1988 User's Guide, what the core does, what evidence exists,
and what is missing. **No RTL was changed for this audit.** Game usage comes from `game_survey.md` (Part 0).

## The two modes have different evidence

Upstream's 160 self-checking benches were all written for, and run with, upstream mode's parameters (the defaults
at the time; since the default switch each bench states them explicitly)
(`CYCLE_ACCURATE=0, CLKS_PER_STATE=1`). The accurate model (`CYCLE_ACCURATE=1, CLKS_PER_STATE=8`) has so far been
checked by the timing bench (1,003 cases; registers and memory identical to upstream mode in all of them), the
random arithmetic runs, and NARC on hardware.

To find out what upstream's benches say about the accurate model, they were run with the defaults flipped (scratch
worktree `~/wt/tms34010_sv_accreg`, never committed). The benches check results after fixed numbers of clocks, and
the accurate core spends 8 clocks per state, so every wait and watchdog was stretched x16 (and a control run of the
same stretched benches in upstream mode shows what the stretching alone breaks).

| Run | Pass | Fail |
|---|---|---|
| Control: stretched benches, upstream mode | 158 | 2 (`tb_addc_subb`, `tb_neg_not`: the stretch lets the program run on past the checks) |
| Stretched benches, accurate mode | 140 | 20 (the same 2 + 18) |
| The 18, waits a further x4 | 143 in all | 17 (the same 2 + 15, explained or open below) |

The 18 accurate-only failures fall into these groups (details in the table further down, filled in once each one is
explained):

- **Not finished at the check** (a register still holds its value from before the instruction): re-run x4 longer.
- **Harness boundary, C6:** the bench drives `tms34010_core` directly with a plain memory model. In accurate mode
  plane masking and transparency are done by the field sequencer in the memory fabric (C6, `cycle_accuracy.md`),
  which a core-only bench doesn't have. These need re-running at system level, not "fixing".
- **Word engines:** in accurate mode FILL/PIXBLT write whole words (13.3.2, C-items in `cycle_accuracy.md`), so
  benches that count or list per-pixel requests see fewer, wider requests.
- **Request-level timing assertions** (counts of refresh cycles or acknowledges in a window): expected to differ.

| Bench | DUT | Accurate-mode result | Verdict |
|---|---|---|---|
| tb_jrcc_unsigned, tb_logical_rr, tb_sub_rr | core | pass with waits x64 | slow, not wrong |
| tb_addk_subk | core | x16: B2 = 0x100; x64: A5 = -16 | **bench timing, not wrong** (REVIEW_7 finding 1): the program ends at about clock 460 in accurate mode, but the bench has no halt loop and its 64-word memory aliases, so the core keeps re-running the program. The check at 300 x waits clocks lands mid-program: word 23 at x16 (MOVI to B2 done, ADDK 16 not yet), word 27 at x64 (MOVI to A5 done, ADDK 32 not yet); x128 and x256 land in the zero area and pass |
| tb_fill_ppop, tb_graphics_ppop_matrix, tb_pixt_pmask, tb_pixt_transp | core | plane-masked / transparent pixels written | harness boundary (C6); **settled at system level**, below |
| tb_array_checkpoint, tb_window_preclip, tb_line_interrupt | core | fewer, wider memory requests than the per-pixel lists expect | word engines (expected); results compared at system level by the timing bench |
| tb_mame_graphics_replay | core | case 120: one memory word differs (0045 vs 9945) | **harness boundary (C6)**: case 120 is `transparent_zero`, a PIXT with transparency, which accurate mode applies in the memory fabric this core-only bench lacks; transparency PIXT is in the system-level matrix (identical in both modes) |
| tb_fetch_walk, tb_host_halt, tb_smoke | core | acknowledge/refresh counts in a fixed window; a FETCH clock without a request | request-level timing checks (expected) |
| tb_system_fabric | system | screen-refresh address 0x011F where the bench expects 0x0120; an IAQ check (immediate words fetched with IAQ high) | **bench timing** (2026-10-06): the first refresh is 0120 as expected; the bench keeps the last of several. It programs HTOTAL 7, VTOTAL 3 with VCLK = core clock: an 8-clock line (one state in accurate mode) and a 32-clock frame, shorter than a 2-state screen-refresh cycle, so a refresh completes after the next frame has reloaded DPYADR and steps the new value (011F from then on). Upstream mode passes because its bus cycle is one clock. Not reachable with real video timing; noted: a refresh that completes after a frame reload steps the reloaded address. IAQ: the same case as tb_pixel_srt below (11-24) |
| tb_pixel_srt, tb_pin_system | system / pins | immediate (extension) words fetched with IAQ high; PMASK takes its new value before the I/O write's bus cycle ends | IAQ: both are right, for different cases (11-24, below); PMASK: posted I/O write, C7 (6.2) |

**Pixel processing at system level (closes the C6 rows).** `tools/dropin/ppop_matrix.py` makes 2,598 bench cases:
FILL L, PIXBLT L,L, PIXBLT B,L, PIXT Rs,*Rd (non-zero and zero colour) and DRAV, each across every defined PPOP x
PSIZE cell (A0051: Boolean 0x00-0x0F at PSIZE 1/2/4/8/16, arithmetic 0x10-0x15 at 4/8/16), transparency off/on,
plane mask off/on (0x5AA5), with partial first words and two word boundaries per row. Run through
`tms34010_system` in both modes: **registers and memory identical in all 2,598**, including 246 cases with a
source that is not pixel-aligned (the JPM boards do this). The bench runs each case's instruction in a loop of two
passes; the destination is rewritten at the start of each pass, so the memory compared is one application of the
operation (an earlier version wrote it once, which let XOR, XNOR and NOT D undo themselves; REVIEW_4.md finding 3).
940 distinct memory results; transparency and the plane mask change the result in many cells, so the cases do
exercise them.

What equality shows, and what it doesn't: the accurate model's word engines and its read-modify-write merge in the
memory fabric (C6) produce the same memory as upstream's pixel-at-a-time engine, for these cases. Upstream's
`tb_graphics_ppop_matrix` checks the pixel operation function itself (shared by both engines) against an
independent model. It does not check the geometry of these particular cases, and the misaligned-source cases have
no reference other than the two engines agreeing.

**IAQ, settled by the guide: no change needed.** The 1988 guide, 11.5 (p. 11-24): IAQ is high for every word of
a cache-subsegment fill, opcodes and data alike; and "When the cache is disabled, IAQ is active high only when the
first word of an instruction is fetched; in the case of a multiple-word instruction, IAQ is inactive while the
additional words are fetched." Upstream mode (no cache) and accurate mode with the cache off do the second; accurate
mode with the cache does the first. Upstream's pin benches check the cache-off rule, which is why they fail in
accurate mode with the cache on. Both are right. (A change I made overnight that raised IAQ for every immediate
word read the first half of the paragraph and missed the last sentence; the fresh review caught it and it is
reverted, commit 861206d.)

## Checklist

"Games" is from the survey: how many of the surveyed 34010s use the part (see `game_survey.md` for which).

| Guide | Part | Games (of 57) | Evidence now (upstream mode / accurate mode) | Gap, size |
|---|---|---|---|---|
| 2 | Pins | the system-level ports, in every game core | upstream: `tms34010_pin_system`, `tb_pin_system`, `tb_pin_srt` / accurate: pin benches show IAQ on immediates and posted I/O writes differ (above) | IAQ settled by 11-24, no change needed; game cores use the system level, so further pin-level work is for completeness only |
| 3 | Memory: bit addressing, map, stacks | all | upstream benches; timing bench registers and memory equal in both modes (1,003 cases) | none known |
| 4 | Fields, pixels, XY, arrays | all | upstream field/XY benches; both modes equal on the bench | none known |
| 5.1-5.3 | Registers, ST, PC | all | `status_audit.md` (every flag of every instruction), `tb_status_decode` over 65,536 opcodes; bench equality | none known |
| 5.4 | Instruction cache | all (1 turns it off) | accurate only; timing evidence page; cache-off bench 834/158/0 | none: the host bench rewrites a loop instruction; accurate mode keeps running the cached copy until the host sets CF, then runs the new one (5.4.5) |
| 5.5 | Posted writes | all | timing evidence page; the host bench measures the halted instruction's 32-bit store landing up to 1.4 states after the halt (4.4 with an earlier loop, REVIEW_4.md); the guide gives no figure for this | none |
| 6 | I/O registers | all | upstream `tb_io_*`; 6.2 posted I/O write (C7) | REFCNT/DPYADR/HCOUNT reads (games read HCOUNT/VCOUNT, DPYADR) in accurate mode not separately checked (small) |
| 7.1-7.9 | Pixel operations, transparency, plane mask, PBH/PBV | Replace/T in 48; MAX/MIN/NOT S AND D in 4; PBH/PBV in 3; PMASK in none | upstream `tb_graphics_ppop_matrix` (independent model); **system-level matrix, 2,598 cases equal in both modes** | timing at PSIZE 1/2 (Atari) to check against Table 13 figures (medium) |
| 7.10 | Windows W=1/W=3, violation | W=3 in 28, W=1 in 5, W=2/WV never | upstream `tb_*_window`, `tb_window_preclip`, `tb_window_common_rect`; bench window cases; **negative coordinates** (2026-10-09, `tb_negxy_sys`: 156 cases of FILL XY, PIXBLT L/XY/B,XY, PIXT, DRAV and LINE starting above or left of (0,0), against the guide's rules, both modes) | fixed 2026-10-09: upstream compared X/Y unsigned and formed the W=3 clipped start from the unclipped corner (accuracy_evidence.md section 3); accurate W=3 timing items C14-C16 (medium; Atari) |
| 7 / 12.6 | LINE, DRAV, PIXT forms | LINE 10, DRAV 10, PIXT 7 forms | upstream per-form benches; bench cases | LINE timing C10 confirmed only for the printed cases (medium; Atari) |
| 8 | Interrupts, NMI, traps, illegal opcodes, reset | DI 53, INT1 25, INT2 7, HI 5, NMI 3 (NMIM=1) | upstream `tb_int_*`, `tb_nmi*`, `tb_trap*`, `tb_illegal_opcode`; accurate: interrupt entry timing (evidence page), host bench NMI and INTIN | none: NMI with NMIM=1 through the system leaves SP unchanged (host bench) |
| 9 | Video timing, interrupts, SRT, external sync, interlace | all program video; SRT 44; external sync 4; interlace 3; HSD 3 | upstream `display_conformance.md`, `srt_conformance.md`, video benches; video logic has no mode parameter | two-GSP external sync checked at video-timing level for HEBLNK1 >= 3, including the Exterminator's own register values (2026-10-06, `tb_two_gsp_sync`, below), and at system level with both CPUs programming their registers, both modes (2026-10-08, `tb_two_gsp_sys`, below); HEBLNK1 < 3 not supported (below) |
| 10 | Host interface | 21 | upstream `tb_host_*` (engine and core level); **system-level host bench, both modes**: load/readback, HLT, 64 indirect accesses running, NMI (NMIM 0 and 1), INTIN, INTOUT/HINT, CF, LBL=1; indirect cycles 2.1-6.0 states while running (10.5 gives 7 without the 2T synchroniser). Halt: 0.12-3 states after the port accepts HSTCTL, which is less than Table 10-2's 1-state minimum for recognition: the system-level port has no synchroniser for HLT (the host is already synchronous there; `tms34010_host_bus` adds one at pin level). An integrator who needs the chip's figure adds 1-2 states of synchronisation | done in the host bench: LBL=1 (address written high then low into a new page; a mutant that ignores LBL fails it), CF, INTOUT/HINT. Byte-wide hosts (single-byte accesses) not exercised: no surveyed host is 8-bit. The bench never drives the guide's worst cases (refresh and screen refresh colliding with a host cycle) |
| 11 | Local memory: priorities, cycles, refresh, hold | all (RM=1 in 40) | timing evidence page (cycle timing); upstream arbiter/refresh benches | refresh and screen-refresh priorities against the CPU in accurate mode measured only indirectly (medium) |
| 12 | Instruction set | 134 of 139 forms used | upstream per-instruction benches; random MPY/DIV/MOD vs the guide; bench equality | none known (MODS N follows the status table) |
| 13 | Instruction timing | all | evidence page: 874 match, 129 noted, 0 unexplained | C17 (misaligned linear FILL/PIXBLT destination hangs in accurate mode; out of spec, no game seen to do it) |
| A | Electrical / AC timing | - | not modelled | out of scope: an FPGA has no analog pins |
| C | TMS34020 | - | not modelled | out of scope: a different chip (X-unit, Battletoads, Metal Maniax, Atronic boards) |
| - | Upstream non-goals: first-silicon modes, external VRAM serial pixels | - | not modelled | out of scope; no surveyed board needs them in the core |

**Defaults (since the switch):** `tms34010_system`, `tms34010_core` and `tms34010_memory_fabric` default to
accurate mode (`CYCLE_ACCURATE=1, CLKS_PER_STATE=8`); every upstream bench sets upstream mode explicitly. Kevin's
pin-level wrapper (`tms34010_pin_system`) and Cyclone V board top keep upstream mode as their default: accurate mode
was checked at pin level on 2026-10-08 (below): it works there, but its bus timing does not survive the
wrapper, so accurate mode is for the system level (which is what game cores use).

**Accurate mode at pin level (2026-10-08).** `tb_pin_system` run with `tms34010_pin_system #(.CLKS_PER_STATE(8),
.CYCLE_ACCURATE(1))` and the core clock at the 8x bus clock: the boot (eight reset RAS cycles), program fetches,
host-bus PMASK accesses and physical HOLD/HLDA all work. Its failures are the IAQ and PMASK items above (11-24, C7)
and watchdogs that count core clocks (100 core clocks is 100 states in upstream mode but 12.5 here; scaled by 8 they
pass). The timing does not carry through: back-to-back memory cycles appear on the pins 4 states apart (20 of 32
intervals; the rest longer), where the chip and the system-level model take 2. Upstream mode at pin level gives 8.
The wrapper passes each request through a clock-domain bridge (two-phase handshake, 2-flop synchronisers each way)
to a separate pin engine that starts the cycle at its own next state and answers back through the bridge; the core
then aligns its next request to its own state grid. Those two crossings and two alignments cost about 2 states per
cycle. A fix would run the pin engine on the core's clock in accurate mode, without the bridge, with its quarter
phases locked to the core's state counter. Not done (Chris, 2026-10-08): only an FPGA used in place of a real chip on
a physical board needs pin timing, and no game core does that. **Known limit: in accurate mode use
`tms34010_system`; `tms34010_pin_system` is functional only.**

**Size and speed (B1):** `dropin_measure.md`. at d67fc17, 14,292 ALMs and 55.56 MHz in accurate mode
(seed 1; 0d0cff4 gave 57.59/56.32 on seeds 1/2), against a target of at least 55 MHz. The worst path runs from PSIZE
into the register-file family.

**Two GSPs in external sync (9.9.1, Table 9-1; Exterminator).** `sim/tb/tb_two_gsp_sync.sv` connects two video
timing units: GSP #1 internal (DXV=1), GSP #2 external (DXV=0, HSD=0) on GSP #1's HSYNC/VSYNC, GSP #2 programmed as
Table 9-1. BLANK and HBLANK are equal on every clock of four frames, for two sets of timing values and for the
Exterminator's own: the MAME survey records the game writing exactly Table 9-1 (master HEBLNK/HSBLNK 0x28/0x128,
slave 0x25/0x125, slave HESYNC/VESYNC half way, HTOTAL/VTOTAL 0xFFFF). The internal VBLANK flags differ only for the
3 clocks by which GSP #2's line starts later (the guide: HCOUNT2 is cleared three VCLK periods after HCOUNT1),
always inside horizontal blanking. That skew is the model's, not the chip's: in external sync the chip ends
vertical blanking when it detects the external HSYNC (6-49); it is harmless while horizontal blanking covers it.
Limit (REVIEW_7 finding 2): only HEBLNK1 >= 3 works. Below that HEBLNK2 wraps past HSBLNK2, and `tms34010_video`'s
window compares (`hcount <= heblnk || hcount > hsblnk`) blank GSP #2's whole line, where the guide's set/reset on
equality (9-6) would not; the guide's own worked example (HEBLNK1 = 1) is such a case. No surveyed game does it
(the only two-GSP game in the survey, the Exterminator, uses HEBLNK1 = 0x28).

At system level (`sim/dropin/tb_two_gsp_sys.sv`, run with `tools/dropin/two_gsp_sys.sh 0|1`): two `tms34010_system`
instances, each with its own memory and a program (`tools/dropin/two_gsp_prog.py`) that writes the Exterminator's
video registers (GSP #1 DPYCTL 0xF010, GSP #2 0xD010: external sync, screen refresh on) and then runs a store loop.
GSP #2 leaves reset 1,237 clocks after GSP #1 and locks to its HSYNC/VSYNC pins. BLANK and HBLANK are equal on every
clock of four frames in both modes (and with GSP #2 starting 77,777 clocks later), with screen-refresh and store
traffic running on both. With GSP #2's sync inputs left unconnected (+NOSYNC) the check fails. With 2 or 4 instead of Table 9-1's 3 the bench
fails. The guide's worked example (HSBLNK2 = HTOTAL1-8 for HSBLNK1 = HTOTAL1-4, i.e. 4) disagrees with its own
table and with "three full VCLK periods"; the model follows the table. Video logic has no mode parameter, so this
holds in both modes.
