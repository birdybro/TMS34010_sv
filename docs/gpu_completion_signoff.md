# Production-revision GPU completion sign-off

## Claim

Task 0174 signs off the functional production-revision TMS34010 Graphics
System Processor scope frozen by Task 0161. Within that scope, no behavior
defined by the 1988 TI TMS34010 User's Guide remains unimplemented, marked
`TBD`, or supported only by an untested claim. Every source row below has an
RTL owner and named self-checking evidence, and every Task 0162–0173 gate is
complete.

This is a functional processor and FPGA-boundary claim. It is not a claim of
cycle-for-cycle equivalence with original silicon or of a complete external
video board.

## Authoritative source audit

The primary architecture source is
`third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf`.
SPVS002C in `third_party/TMS34010_Info/docs/datasheets/` is authoritative for
the matching production processor pins and AC diagrams. MAME and preserved TI
programs are independent integration witnesses, not substitutes for those
sources.

| Defined production area | Source boundary | RTL ownership | Complete evidence ledger |
|---|---|---|---|
| Chapter 6 graphics registers and B-file meanings | CONTROL, CONVSP, CONVDP, PSIZE, PMASK, DPYCTL.SRT, B0–B14 | I/O register file, regfile, and shared graphics setup/writeback in `tms34010_core.sv` | Every field in `graphics_conformance.md`; `tb_io_regs`, `tb_graphics_ppop_matrix`, and the engine-focused suites |
| Chapter 7 addressing and pixel rules | XY conversion, pixel size, COLOR selection, PMASK, PPOP, transparency, window modes, PBH/PBV, array and interrupt context | Pixel address/field sequencer, shared pixel processor, FILL/PIXBLT/LINE/PIXT/DRAV state in `tms34010_core.sv` | 1,176 defined PPOP/PSIZE/backend cells plus 10 PMASK-read cells; direction, array-edge, W=1, W=3, checkpoint, LINE-interrupt, and SRT suites in `graphics_conformance.md` |
| Individual graphics instructions | ADDXY, SUBXY, CMPXY, CPW, CVXYL, every PIXT form, DRAV, LINE, both FILL forms, and all six PIXBLT forms | Decoder, core datapaths/FSMs, status register, and field sequencer | Per-form Chapter 12 rows and named tests in `graphics_conformance.md`, `instruction_coverage.md`, and `status_audit.md` |
| Chapter 9 display behavior | Programmed/live registers, internal/external sync, noninterlace/interlace, ENV/DIP, blanking, screen cadence, DPYADR/DPYTAP/ORG/DUDATE | Video, display-address, I/O, subsystem, screen CDC, and local-bus modules | Every register/mode row in `display_conformance.md`; generated 577-case scheduler oracle and video/display/CDC/pad suites |
| Graphics interruption and continuation | Destination-word/row checkpoints, DI/NMI entry, PBX array reconstruction, ordinary LINE restart, repeated interruption, RETI | Core checkpoint, interrupt-entry, resume, and writeback states | `tb_array_checkpoint`, `tb_line_interrupt`, `tb_int_reti`, `tb_nmi_nopush`; exact uninterrupted-versus-resumed request suffixes under stalls |
| Chapter 11 local-bus cycles associated with graphics/display | Ordinary field cycles, screen MTR, program MTR/RTM, LRDY extension, HOLD/restart, arbitration and CDC | Field sequencer, fabric/arbiter, local-bus bridge, phase engine, pin system | Every phase row in `srt_conformance.md`; `tb_local_bus`, `tb_pin_srt`, `tb_pin_system`, HOLD/RMW, system-fabric, and final-ratio suites |
| Production physical boundary | 63 host, local-bus, video, reset, and clock pins; active-low sync/blank; tri-state ownership | Cyclone V top, PLL/reset wrappers, and FPGA I/O owner | `tb_fpga_io`, `tb_fpga_reset`, `fpga/PINOUT.md`, and the clean Quartus fit/report validator |

Reserved encodings, reserved PPOP/PSIZE combinations, and TI-declared
undefined cases are not assigned invented compatibility behavior. Where an
FPGA requires deterministic behavior, the isolated choice and its source
boundary are recorded in `assumptions.md`, `status_audit.md`, or the relevant
conformance matrix.

## Ordered closure results

| Task | Closed gate |
|---:|---|
| 0162 | Empty FILL/PIXBLT arrays and exact terminal context |
| 0163 | PBH/PBV direction, corner selection, terminal context, and safe overlap |
| 0164 | W=1 common-rectangle queries |
| 0165 | W=3 up-front array preclipping |
| 0166 | Coherent FILL/PIXBLT architectural checkpoints |
| 0167 | PBX array interrupt/RETI reconstruction |
| 0168 | Interruptible LINE continuation |
| 0169 | Complete graphics instruction/register/PPOP/PMASK matrix |
| 0170 | Complete display/video register, mode, address, and pin matrix |
| 0171 | SRT classification through arbitration, CDC, and original-pin MTR/RTM |
| 0172 | Exact-revision MAME differential corpus |
| 0173 | Five preserved TI graphics-software workloads and compatibility fixes |
| 0174 | Repository-wide re-audit, final RTL implementation closure, all software/reference gates, and clean Cyclone V implementation |

Task 0174 also registers the remaining processor-I/O, field/M2M, PIXBLT
resume, and W=3 geometry paths, captures graphics configuration at execute,
and shares one pixel processor among mutually exclusive engines. These are
functionally regression-locked implementation changes that close timing while
retaining the Task 0160 resource envelope.

## Final validation evidence

| Gate | Final result |
|---|---|
| Strict RTL lint | PASS, zero diagnostics |
| Self-checking regression | PASS, 159/159 discovered benches |
| Generated graphics processing matrix | PASS, 1,186/1,186 cases |
| Generated display scheduler matrix | PASS, 577/577 cases and 579 completed transactions |
| Pinned MAME live differential | PASS, 137/137 cases, 156 classified case/field groups, zero unexplained |
| Preserved TI live workloads | PASS, 5/5 milestones, 9 classified case/field groups, zero unexplained; original ROM rebuild load image identical |
| Quartus Prime Lite 17.0.2 | PASS from clean map, fit, assembly, and multicorner TimeQuest; report validator PASS |
| Physical fit | 63/63 pins, 12,645/41,910 ALMs (30%), 10,479 registers, 0 memory bits, 6/112 DSPs, 2/6 PLLs |
| Timing | +0.556 ns worst setup, +0.147 ns worst hold, +1.250 ns minimum-pulse slack, zero TNS, zero ignored constraints |
| CDC | 27 required two-stage chains / 54 forced stages present, 375 detected candidates, 242-year worst required-chain MTBF |
| Accepted Quartus diagnostics | Map/assembler/TimeQuest zero warnings; fitter only `177007`, `177007`, `292013` |
| Refresh-service bound | Worst observed 11 of 32 core clocks with HOLD inactive and bounded-ready LRDY |

The reproducible hardware command and timestamp-free report record are in
`fpga/IMPLEMENTATION_EVIDENCE.md`. The differential and workload commands,
provenance, hashes, result locks, and closed divergence classifiers are in
`mame_graphics_reference.md` and `ti_workloads.md`.

## Explicit non-goals

The GPU-complete claim does not include:

- the optional instruction cache or cache-dependent cycle behavior;
- exact instruction-cycle parity with original silicon;
- first-silicon-only modes or errata compatibility;
- TMS34020, TMS34082, or other later-family behavior;
- external VRAM/DRAM storage models or VRAM serial-pixel generation;
- a palette/RAMDAC, monitor pipeline, or other surrounding video devices;
- board-level level translation, buffering, termination, signal integrity,
  power integrity, or analog validation.

These exclusions are optional extensions or surrounding-system
responsibilities. They are not open production TMS34010 processor behavior.

## Sign-off conclusion

The Task 0161 production-revision GPU scope is complete. Every defined
graphics/display register, pixel rule, graphics instruction, display mode,
interrupt/resume behavior, and associated processor pin cycle has a
primary-source mapping, implemented RTL owner, and passing direct evidence.
Independent reference and preserved-software differences are fully
classified with zero unexplained mismatch, and the final Cyclone V build
passes the frozen resource, pin, CDC, service, and multicorner timing gates.
