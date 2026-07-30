# Display and video conformance matrix

> Status: **closed for the production TMS34010 revision through Task 0170**.
> Every production display register, timing mode, automatic screen-refresh
> event, and processor-side video pin has a primary source, an RTL owner, and
> named self-checking evidence below.

The authority is the 1988 TI TMS34010 User's Guide at
`third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf`.
Chapter 6 defines the register contract and Chapter 9 defines the complete
video sequencer and screen-refresh address network. The SPVS002C data sheet
at `third_party/TMS34010_Info/docs/datasheets/` supplies the production pin
descriptions and AC diagrams. The pinned MAME revision in
`third_party/TMS34010_Info/emulation/mame/UPSTREAM.md` is secondary evidence,
not the authority.

`video` below means `rtl/video/tms34010_video.sv`; `display` means
`rtl/video/tms34010_display_addr.sv`; `subsystem` means
`rtl/video/tms34010_video_subsystem.sv`; `I/O` means
`rtl/io/tms34010_io_regs.sv`; and `local bus` means
`rtl/memory/tms34010_local_bus.sv`.

## Production register matrix

All listed registers are 16-bit and reset to zero. Ordinary programmed
registers read back their stored value. HCOUNT, VCOUNT, and DPYADR are live
VCLK-owned registers; their FPGA CDC contract is called out separately.

| Register / field | Primary source | Access and exact live-update point | RTL owner and named evidence |
|---|---|---|---|
| HESYNC [15:0] | 6-28; §§9.3, 9.5 | R/W; a new VCLK-domain snapshot changes the end-sync equality. HSYNC remains active through the count equal to HESYNC and changes on the next update edge. | I/O, subsystem, video; `tb_io_regs`, `tb_video`, `tb_io_video`, `tb_video_cdc` |
| HEBLNK [15:0] | 6-27; §§9.3, 9.5 | R/W; selects the last leading-blank count. HBLANK remains active through equality and becomes inactive at HEBLNK+1. | I/O, subsystem, video; `tb_video`, `tb_io_video`, `tb_video_cdc` |
| HSBLNK [15:0] | 6-29; §§9.3, 9.5 | R/W; equality is the internal start-HBLANK event for DIP and screen scheduling. The output becomes blank at HSBLNK+1. | I/O, subsystem, video/display; `tb_video`, `tb_io_video`, `tb_display_addr`, `tb_display_matrix` |
| HTOTAL [15:0] | 6-39; §§9.3, 9.5 | R/W; HCOUNT spans 0..HTOTAL and clears on the update edge after equality. Also supplies the missing-HSYNC fallback and interlace half-line point. | I/O, subsystem, video; `tb_video`, `tb_video_interlace`, `tb_video_external_sync` |
| VESYNC [15:0] | 6-50; §§9.3, 9.6 | R/W; VSYNC remains active through the equal VCOUNT line. The odd interlaced field performs its extra VCOUNT step at the VESYNC half-line point. | I/O, subsystem, video; `tb_video`, `tb_video_interlace` |
| VEBLNK [15:0] | 6-49; §§9.3, 9.6 | R/W; VBLANK remains active through equality and the HBLANK at VEBLNK schedules the refresh preceding the first active line. | I/O, subsystem, video/display; `tb_video`, `tb_display_addr`, `tb_display_matrix` |
| VSBLNK [15:0] | 6-51; §§9.3, 9.6 | R/W; VBLANK starts after equality. At `HCOUNT=HSBLNK,VCOUNT=VSBLNK`, SRFADR reloads from DPYSTRT at the end of the last active line. | I/O, subsystem, video/display; `tb_video`, `tb_io_display`, `tb_display_matrix` |
| VTOTAL [15:0] | 6-52; §§9.3, 9.6 | R/W; VCOUNT spans 0..VTOTAL. It supplies normal frame wrap, external missing-VSYNC fallback, and the interlaced field boundary. | I/O, subsystem, video; `tb_video`, `tb_video_interlace`, `tb_video_external_sync` |
| DPYCTL.HSD [0] | 6-19 | R/W; in external mode, 0 selects HSYNC input and 1 selects internally generated HSYNC output. | I/O, subsystem, video/pads; `tb_io_video`, `tb_video_external_sync`, `tb_fpga_io` |
| DPYCTL [1] | 6-19 | Reserved; this implementation masks writes and reads zero. | I/O; `tb_io_regs` |
| DPYCTL.DUDATE [9:2] | 6-20; §§9.10.1.1–9.10.1.3 | R/W one-hot/zero field. A completed screen MTR decrements raw SRFADR by 0/1/2/4/8/16/32/64/128. Interlaced even-field setup subtracts half that raw amount. | I/O, display; `tb_display_addr`, all defined values in `tb_display_matrix`, `tb_video_cdc` |
| DPYCTL.ORG [10] | 6-20; §9.10.1.2, Figure 9-14 | R/W; 0 selects a stored one's-complement SRFADR and inversion at the LAD pins, producing effective upward/increasing display addresses. 1 outputs stored SRFADR directly, producing decreasing addresses. ORG never changes the raw decrement. | I/O, display, local bus; `tb_display_matrix`, `tb_local_bus`, `tb_system_fabric` |
| DPYCTL.SRT [11] | 6-21; §9.10.2 | R/W; converts only program-controlled graphics pixel reads/writes to MTR/RTM. It does not affect screen refresh or DPYTAP. | I/O, graphics engines, fabric/local bus; `tb_pixel_srt`, `tb_pin_srt` and Task 0171's integration matrix |
| DPYCTL.SRE [12] | 6-21; §9.10.1.5 | R/W; a change takes effect at the next start-HBLANK. 0 suppresses new automatic requests; 0→1 forces the next eligible active-line request. | I/O, subsystem, display; `tb_display_addr`, every state in `tb_display_matrix`, `tb_io_display` |
| DPYCTL.DXV [13] | 6-22; §9.9 | R/W; 0 selects external synchronization and 1 selects internal sync generation/output. | I/O, subsystem, video/pads; `tb_io_video`, `tb_video_external_sync`, `tb_fpga_io` |
| DPYCTL.NIL [14] | 6-22; §§9.6.1, 9.6.1.1 | R/W; 1 selects one-field noninterlace and 0 selects the two-field half-line sequence. | I/O, subsystem, video/display; `tb_video_interlace`, `tb_video_external_sync`, `tb_display_matrix` |
| DPYCTL.ENV [15] | 6-22; §§9.5–9.7 | R/W; 0 immediately forces functional blank and inhibits new DIP events without clearing an existing DIP. Counters and refresh continue. | I/O, subsystem, video; `tb_video`, `tb_io_video`, mode cross-product in `tb_video_external_sync` |
| DPYSTRT.LCSTRT [1:0] | 6-24; §9.10.1.5 | R/W; loads LNCNT at the HBLANK preceding the first active line and after each completed screen MTR. Values 0..3 produce one request every 1..4 active lines. | I/O, subsystem, display; every value in `tb_display_matrix`, `tb_display_addr`, `tb_io_display` |
| DPYSTRT.SRSTRT [15:2] | 6-24; §§9.6.1, 9.10.1.2 | R/W; loads raw SRFADR at `HCOUNT=HSBLNK,VCOUNT=VSBLNK`. The reload preceding an even interlaced field subtracts raw DUDATE/2. | I/O, subsystem, display; `tb_display_addr`, `tb_display_matrix`, `tb_io_display` |
| DPYINT [15:0] | 6-23; §§9.5–9.7 | R/W; when ENV=1, equality with VCOUNT sets DIP at the HSBLNK event marking the end of that line. A coincident screen request has bus priority. | I/O, subsystem, video; `tb_video`, `tb_video_interlace`, `tb_io_video`, `tb_video_cdc` |
| DPYTAP [13:0] | 6-25; §§9.10.1.2, 9.10.1.4 | R/W; captured with each automatic request. These are physical column-address/tap bits representing logical screen-address bits beginning at bit 4, not a standalone bit address. DPYTAP[11:6] is ORed with DPYADR[7:2], [5:0] drives LAD[5:0], and [13:12] drives LAD[13:12]. | I/O, display, local bus; `tb_io_regs`, `tb_display_matrix`, both ORG cases in `tb_local_bus`, `tb_io_display` |
| DPYTAP [15:14] | 6-25 | Reserved; this implementation masks writes and reads zero. | I/O; `tb_io_regs`, `tb_io_display` |
| HCOUNT [15:0] | 6-26; §§9.5, 9.9 | Live R/W counter. A delivered processor command has priority over automatic increment/clear on that VCLK edge. | video/subsystem/I/O; `tb_video`, `tb_io_video`, `tb_video_cdc`, `tb_video_external_sync` |
| VCOUNT [15:0] | 6-48; §§9.6, 9.9 | Live R/W counter. A delivered command has priority over external/internal field events and line increment on that VCLK edge. | video/subsystem/I/O; `tb_video`, `tb_io_video`, `tb_video_cdc`, `tb_video_interlace`, `tb_video_external_sync` |
| DPYADR.LNCNT [1:0] | 6-17 | Live R/W scan-line counter. Processor load wins a coincident automatic update; eligible lines decrement it and completed refreshes reload LCSTRT. | display/subsystem/I/O; `tb_display_addr`, `tb_display_matrix`, `tb_io_display`, `tb_video_cdc` |
| DPYADR.SRFADR [15:2] | 6-17/18; §9.10.1.2 | Live R/W raw screen address. It reloads at frame blank, is captured when a request is scheduled, and decrements only after physical MTR completion. | display/subsystem/I/O; `tb_display_addr`, `tb_display_matrix`, `tb_io_display`, `tb_video_cdc`, `tb_local_bus` |

## Timing and mode matrix

| Mode or event | Exact production behavior | Named evidence |
|---|---|---|
| Internal, noninterlaced | HCOUNT wraps after HTOTAL; that line event advances/wraps VCOUNT. Sync and blank outputs transition one update after their programmed equality. | Cycle reference in `tb_video`; integrated `tb_io_video` |
| Internal, interlaced | Reset starts even. Even→odd occurs at `VCOUNT=VTOTAL,HCOUNT=floor(HTOTAL/2)` without clearing HCOUNT. Odd VESYNC advances VCOUNT at the half-line. Odd→even occurs at the full HTOTAL/VTOTAL boundary. | Cycle reference in `tb_video_interlace` |
| External, HSD=0 | Synchronized active-low HSYNC and VSYNC starts clear their counters on the third project update edge. HTOTAL/VTOTAL remain missing-sync limits. | `tb_video_external_sync` |
| External, HSD=1 | HSYNC is internally generated/output and ignores the external HSYNC input; VSYNC remains an input. Vertical fallback therefore uses the internal HTOTAL line boundary. | `tb_video_external_sync`, `tb_io_video` |
| External field classification | At recognized VSYNC, `HEBLNK < HCOUNT <= HSBLNK` selects odd; every other phase selects even. NIL=1 forces even/noninterlaced. | `tb_video_external_sync` |
| Direction pins | `{HSD,DXV}=00` inputs both syncs; `01` outputs both; `10` outputs HSYNC and inputs VSYNC. The undefined `11` case deterministically uses internal/output timing. | Exhaustive cross-product in `tb_video_external_sync`; `tb_fpga_io` |
| ENV and DIP | ENV=0 forces active blank and inhibits new DIP. ENV=1 permits DIP exactly at `HCOUNT=HSBLNK,VCOUNT=DPYINT`; the odd VESYNC half-line collision is suppressed. | `tb_video`, `tb_video_interlace`, `tb_io_video`, `tb_video_cdc` |
| Screen active window | No automatic request occurs in vertical blank. The HBLANK at VEBLNK forces the first request; later requests follow LCSTRT+1 cadence while `VCOUNT < VSBLNK`. | `tb_display_addr`, `tb_display_matrix`, `tb_io_display` |
| Held screen transaction | SRFADR, DPYTAP, and ORG are captured together and held through CDC, arbitration, HOLD/LRDY delay, and the complete local MTR. Only returned completion changes DPYADR. | `tb_display_addr`, `tb_video_cdc`, `tb_system_fabric`, `tb_local_bus` |
| Pin polarity | Functional HSYNC/VSYNC/blank intervals are active high inside the reusable hierarchy. The FPGA pad boundary drives active-low HSYNC, VSYNC, and BLANK package pins and tri-states input-selected sync pins. | `tb_fpga_io`; `tms34010_cyclone_v_top` |
| Reset recovery | Timing/configuration/live state, field phase, DIP mailbox, and screen transaction return to zero/even/inactive; ENV=0 keeps the package display blanked. | All video/display focused benches |

`tb_display_matrix` executes 577 scheduler cases: the complete
NIL/field/ORG/SRE/LCSTRT cross-product at all nine defined DUDATE values,
plus the documented deterministic multi-bit DUDATE case. It validates 579
captured request/complete transactions, raw address values, exact cadence,
tap masking, live completion control, and reset between cases.

## Screen-address representation

The guide uses “increment” in descriptions of the effective display address,
but Figure 9-14 states the hardware representation precisely:

1. DPYSTRT/DPYADR store the one's complement of the address when ORG=0 and
   the direct address when ORG=1.
2. The raw DPYADR SRFADR field is decremented by DUDATE after every completed
   screen transfer, for both ORG values.
3. The local-bus path complements raw SRFADR only when ORG=0.
4. DPYTAP supplies and ORs the low physical column/tap portion. The resulting
   screen address covers logical address bits 4–23.

Thus ORG=0 is an effective increment and ORG=1 is an effective decrement,
without two different counter update directions. The pinned MAME TMS34010
path independently uses the same raw subtract and ORG=0 complement; MAME's
interlaced video path is explicitly unsupported and was not used to fill any
TI-defined field behavior.

## Deliberate FPGA boundary choices

- The original HCOUNT/VCOUNT/DPYADR interface is unsynchronized and TI says
  software can reliably access it only while VCLK is held high. This FPGA
  keeps VCLK free-running: writes use a coherent coalescing command mailbox
  and reads use a coherent bounded-stale `{HCOUNT,VCOUNT,DPYADR}` snapshot.
  No binary value is sampled bit-torn.
- Configuration writes cross as atomic snapshots. Multiple writes while the
  mailbox is occupied coalesce to the latest complete register image.
- A same-VCLK DPYADR load wins over frame, cadence, or completion updates; a
  valid completion still retires its request. Clearing SRE does not cancel a
  request already issued.
- TI declares multi-bit DUDATE and `{HSD,DXV}=11` undefined. Multi-bit DUDATE
  is an unsigned raw decrement; the direction combination selects internal
  output timing.
- DPYCTL bit 1 and DPYTAP bits 15:14 read zero rather than retaining ignored
  writes. This is the project-wide deterministic reserved-field policy.
- Synchronous active-high reset and the VCLK active-edge representation are
  FPGA implementation choices documented in A0003/A0045. The production top
  maps that edge to falling VIDEO_VCLK and maps all active-low video pins.

## Processor boundary and external system

The TMS34010-side display implementation is complete at VIDEO_VCLK,
HSYNC/VSYNC/BLANK, and the local-bus MTR pins. The processor supplies timing,
screen addresses, arbitration, and the physical transfer that loads attached
VRAM shift registers. Serial shifting inside those VRAMs, pixel
serialization, palette/RAMDAC conversion, monitor timing outside the
processor pins, level shifting, and analog board validation are surrounding
system behavior—not missing TMS34010 RTL.
