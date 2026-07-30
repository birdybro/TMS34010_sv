# DE10-Nano pinout

The Quartus top is `tms34010_cyclone_v_top` on Cyclone V
`5CSEBA6U23I7`. Pin locations come from the Terasic DE10-Nano User Manual:
Table 3-5 for the two 50 MHz clocks, Table 3-7 for debounced active-low
KEY0, and Table 3-10 for the JP1/JP7 expansion headers. The pinout uses all
36 FPGA signals on JP1 and the first 24 on JP7.

The headers and FPGA banks are **3.3 V only**. This is a logical TMS34010
signal map, not permission to wire an original processor bus directly to the
board. A physical system must provide bidirectional level translation,
appropriate drive/fanout, pull-ups where required, series termination as
shown necessary by signal-integrity analysis, and a common ground. Header
power pins are not FPGA I/O and are not listed below.

The top-level port retains the package label `BLANK`, but its electrical
polarity is active low, matching the original TMS34010 pin.

## Board-owned inputs

| Top port | Board signal | FPGA pin |
|---|---|---|
| `FPGA_CLK1_50` | 50 MHz clock 1 | `PIN_V11` |
| `FPGA_CLK2_50` | 50 MHz clock 2 | `PIN_Y13` |
| `RESET_N` | KEY0, active low and debounced | `PIN_AH17` |

## JP1 / GPIO_0

| GPIO | Header pin | FPGA pin | TMS34010 top port |
|---:|---:|---|---|
| 0 | 1 | `PIN_V12` | `RUN_EMU_N` |
| 1 | 2 | `PIN_E8` | `HCS_N` |
| 2 | 3 | `PIN_W12` | `HREAD_N` |
| 3 | 4 | `PIN_D11` | `HWRITE_N` |
| 4 | 5 | `PIN_D8` | `HLDS_N` |
| 5 | 6 | `PIN_AH13` | `HUDS_N` |
| 6 | 7 | `PIN_AF7` | `HFS[0]` |
| 7 | 8 | `PIN_AH14` | `HFS[1]` |
| 8–23 | 9, 10, 13–26 | `PIN_AF4` … `PIN_AB23` | `HD[0]` … `HD[15]` |
| 24 | 27 | `PIN_AA19` | `HRDY` |
| 25 | 28 | `PIN_W11` | `HINT_N` |
| 26 | 31 | `PIN_AA18` | `LINT1_N` |
| 27 | 32 | `PIN_W14` | `LINT2_N` |
| 28 | 33 | `PIN_Y18` | `HOLD_N` |
| 29 | 34 | `PIN_Y17` | `HLDA_EMUA_N` |
| 30 | 35 | `PIN_AB25` | `VIDEO_VCLK` |
| 31 | 36 | `PIN_AB26` | `HSYNC_N` |
| 32 | 37 | `PIN_Y11` | `VSYNC_N` |
| 33 | 38 | `PIN_AA26` | `BLANK` |
| 34 | 39 | `PIN_AA13` | `LRDY` |
| 35 | 40 | `PIN_AA11` | `LCLK1` |

JP1 header pins 11/12 and 29/30 are power/ground rather than GPIO, which is
why the compact ranges above skip them.

## JP7 / GPIO_1

| GPIO | Header pin | FPGA pin | TMS34010 top port |
|---:|---:|---|---|
| 0 | 1 | `PIN_Y15` | `LCLK2` |
| 1–16 | 2–10, 13–19 | `PIN_AC24` … `PIN_AG24` | `LAD[0]` … `LAD[15]` |
| 17 | 20 | `PIN_AH22` | `RAS_N` |
| 18 | 21 | `PIN_AH21` | `LAL_N` |
| 19 | 22 | `PIN_AG21` | `CAS_N` |
| 20 | 23 | `PIN_AH23` | `WE_N` |
| 21 | 24 | `PIN_AA20` | `TR_QE_N` |
| 22 | 25 | `PIN_AF22` | `DEN_N` |
| 23 | 26 | `PIN_AE22` | `DDOUT` |

JP7 GPIO numbering—not a compressed table range—is authoritative. The QSF
contains each individual FPGA location assignment.
