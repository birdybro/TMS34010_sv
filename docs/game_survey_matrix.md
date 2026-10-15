# Game survey matrix

Generated from the counting-MAME runs (`game_survey.md`, 0.2). Each cell: how many of that family's surveyed
34010s use the item at least once in 5 minutes of attract mode and random play. Families with a host CPU list
only the 34010s.

### Graphics instructions and pixel processing (pixel-writing instructions only)

| | Z/Y-unit (9) | T-unit (5) | W-unit (6) | Atari GSP (7) | Exterminator (2) | ICE (5) | Cool Pool (3) | Tickee (6) | Skimaxx (1) | X the Ball (1) | Micro3D (3) | JPM Impact (3) | Art & Magic (3) | Inder (3) | all |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pixel op: replace | 9 | 5 | 6 | 7 | 2 |  | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 52 |
| pixel op in PIXBLT: replace | 9 | 5 | 6 | 7 | 2 |  | 3 | 6 | 1 | 1 | 3 | 3 |  | 3 | 49 |
| transparency (T=1) in a graphics instruction | 9 | 5 | 6 | 7 | 2 |  | 3 | 5 | 1 | 1 | 3 | 3 |  | 3 | 48 |
| pixel size 8 during graphics instructions | 9 | 5 | 6 | 7 | 2 |  | 2 | 6 |  | 1 | 3 | 3 |  | 2 | 46 |
| pixel op in PIXT: replace | 9 | 5 | 6 | 7 | 2 |  | 3 | 1 |  | 1 | 3 | 2 | 3 | 1 | 43 |
| pixel op in FILL: replace | 7 | 5 | 6 | 7 | 2 |  | 3 | 1 |  | 1 | 3 | 3 | 3 |  | 41 |
| graphics: PIXBLT B,XY | 9 | 5 | 6 | 7 | 2 |  | 3 |  |  | 1 | 3 | 3 |  |  | 39 |
| graphics: PIXT *Rs,Rd | 9 | 5 | 6 | 7 | 2 |  | 2 |  |  | 1 |  |  | 3 | 1 | 36 |
| graphics: FILL XY | 7 | 3 | 4 | 7 | 2 |  | 3 |  |  | 1 | 3 | 3 |  |  | 33 |
| window mode W=3 |  |  |  | 7 |  |  | 3 | 6 | 1 | 1 | 1 | 3 | 3 | 3 | 28 |
| graphics: FILL L |  | 2 | 2 | 7 |  |  | 3 | 1 |  | 1 |  | 2 | 3 |  | 21 |
| graphics: PIXBLT L,XY |  |  |  | 7 | 2 |  | 2 |  |  | 1 | 3 | 3 |  | 3 | 21 |
| graphics: PIXT Rs,*Rd.XY | 5 |  |  | 5 |  |  | 2 | 1 |  | 1 | 3 | 2 |  |  | 19 |
| graphics: PIXBLT L,L |  |  |  |  | 1 |  | 3 | 6 | 1 | 1 |  | 3 |  | 2 | 17 |
| pixel size 16 during graphics instructions |  | 2 | 2 |  | 1 |  |  | 4 | 1 | 1 |  |  | 3 |  | 14 |
| graphics: DRAV | 6 |  |  | 1 | 1 |  | 2 |  |  |  |  |  |  |  | 10 |
| graphics: LINE |  |  |  | 7 |  |  | 1 |  |  |  | 2 |  |  |  | 10 |
| pixel op in DRAV: replace | 6 |  |  | 1 | 1 |  | 2 |  |  |  |  |  |  |  | 10 |
| pixel op in LINE: replace |  |  |  | 7 |  |  | 1 |  |  |  | 2 |  |  |  | 10 |
| graphics: PIXT Rs,*Rd |  |  |  | 7 |  |  |  |  |  |  |  |  |  | 1 | 8 |
| pixel size 2 during graphics instructions |  |  |  | 5 |  |  |  |  |  |  |  |  |  |  | 5 |
| window mode W=1 |  |  |  |  |  |  | 2 |  |  |  |  | 3 |  |  | 5 |
| graphics: PIXBLT XY,L |  |  |  |  |  |  |  |  |  | 1 | 3 |  |  |  | 4 |
| PIXBLT/FILL direction PBH=1 |  |  |  |  | 1 |  | 2 |  |  |  |  |  |  |  | 3 |
| graphics: PIXT *Rs.XY,*Rd.XY |  |  |  | 2 |  |  | 1 |  |  |  |  |  |  |  | 3 |
| graphics: PIXT *Rs.XY,Rd |  |  |  |  |  |  | 2 |  |  | 1 |  |  |  |  | 3 |
| PIXBLT/FILL direction PBV=1 |  |  |  |  | 1 |  | 1 |  |  |  |  |  |  |  | 2 |
| pixel op in FILL: MAX | 1 |  |  |  |  |  |  |  |  | 1 |  |  |  |  | 2 |
| pixel op: MAX | 1 |  |  |  |  |  |  |  |  | 1 |  |  |  |  | 2 |
| pixel size 1 during graphics instructions |  |  |  | 2 |  |  |  |  |  |  |  |  |  |  | 2 |
| pixel size 4 during graphics instructions |  |  |  |  |  |  | 1 |  |  |  |  |  |  | 1 | 2 |
| graphics: PIXBLT B,L |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  | 1 |
| graphics: PIXBLT XY,XY |  |  |  |  |  |  | 1 |  |  |  |  |  |  |  | 1 |
| graphics: PIXT *Rs,*Rd |  |  |  |  |  |  | 1 |  |  |  |  |  |  |  | 1 |
| pixel op in FILL: MIN |  |  |  |  |  |  | 1 |  |  |  |  |  |  |  | 1 |
| pixel op in FILL: NOT S AND D |  |  |  |  | 1 |  |  |  |  |  |  |  |  |  | 1 |
| pixel op: MIN |  |  |  |  |  |  | 1 |  |  |  |  |  |  |  | 1 |
| pixel op: NOT S AND D |  |  |  |  | 1 |  |  |  |  |  |  |  |  |  | 1 |

### Interrupts

| | Z/Y-unit (9) | T-unit (5) | W-unit (6) | Atari GSP (7) | Exterminator (2) | ICE (5) | Cool Pool (3) | Tickee (6) | Skimaxx (1) | X the Ball (1) | Micro3D (3) | JPM Impact (3) | Art & Magic (3) | Inder (3) | all |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| interrupt enabled: DIE | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 |  | 1 | 3 |  | 3 | 3 | 53 |
| interrupt taken: DI (display) | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 |  | 1 | 3 |  | 3 | 3 | 53 |
| interrupt enabled: X2E | 6 | 4 | 6 |  |  | 5 | 3 | 4 |  | 1 |  |  |  |  | 29 |
| interrupt enabled: X1E | 5 | 4 | 6 |  |  | 5 |  | 5 |  | 1 |  |  |  |  | 26 |
| interrupt taken: INT1 | 5 | 4 | 6 |  |  | 5 |  | 5 |  |  |  |  |  |  | 25 |
| interrupt taken: INT2 |  |  |  |  |  |  | 3 | 3 |  | 1 |  |  |  |  | 7 |
| interrupt enabled: HIE |  |  |  |  |  |  |  |  |  |  | 3 | 2 |  |  | 5 |
| interrupt taken: NMI (NMIM=1) |  |  |  |  | 1 |  |  |  |  |  |  | 2 |  |  | 3 |

### Host interface (from the host side, and HSTCTL bits the 34010 writes)

| | Z/Y-unit (9) | T-unit (5) | W-unit (6) | Atari GSP (7) | Exterminator (2) | ICE (5) | Cool Pool (3) | Tickee (6) | Skimaxx (1) | X the Ball (1) | Micro3D (3) | JPM Impact (3) | Art & Magic (3) | Inder (3) | all |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| host writes HSTADRH |  |  |  | 7 | 1 |  |  |  | 1 |  | 3 | 3 | 3 | 3 | 21 |
| host writes HSTADRL |  |  |  | 7 | 1 |  |  |  | 1 |  | 3 | 3 | 3 | 3 | 21 |
| host writes HSTDATA |  |  |  | 7 | 1 |  |  |  | 1 |  | 3 | 3 | 3 | 3 | 21 |
| HSTCTLH INCW=1 written by the 34010 |  |  |  | 7 | 1 |  |  |  |  |  | 3 | 3 | 3 | 3 | 20 |
| host sets INCW in HSTCTL |  |  |  | 7 | 1 |  |  |  |  |  | 3 | 3 | 3 | 3 | 20 |
| host writes HSTCTL |  |  |  | 7 | 1 |  |  |  |  |  | 3 | 3 | 3 | 3 | 20 |
| host reads HSTCTL |  |  |  | 7 |  |  |  |  |  |  | 3 | 3 | 3 | 2 | 18 |
| host reads HSTDATA |  |  |  | 5 |  |  |  |  | 1 |  | 3 | 3 | 3 | 3 | 18 |
| HSTCTLH HLT=1 written by the 34010 |  |  |  | 7 | 1 |  |  |  |  |  |  | 3 | 3 | 3 | 17 |
| host sets HLT in HSTCTL |  |  |  | 7 | 1 |  |  |  |  |  |  | 3 | 3 | 3 | 17 |
| HSTCTLH INCR=1 written by the 34010 |  |  |  | 7 |  |  |  |  |  |  |  | 3 | 3 | 3 | 16 |
| host reads HSTADRH |  |  |  | 7 |  |  |  |  |  |  |  | 3 | 3 | 3 | 16 |
| host reads HSTADRL |  |  |  | 7 |  |  |  |  |  |  |  | 3 | 3 | 3 | 16 |
| host sets INCR in HSTCTL |  |  |  | 7 |  |  |  |  |  |  |  | 3 | 3 | 3 | 16 |
| HSTCTLH CF=1 written by the 34010 |  | 1 |  | 7 | 1 |  |  |  |  |  |  |  | 3 | 3 | 15 |
| host sets CF in HSTCTL |  |  |  | 7 | 1 |  |  |  |  |  |  |  | 3 | 3 | 14 |
| HSTCTLH LBL=1 written by the 34010 |  |  |  | 7 |  |  |  |  |  |  |  |  |  | 3 | 10 |
| host sets LBL in HSTCTL |  |  |  | 7 |  |  |  |  |  |  |  |  |  | 3 | 10 |
| host sets INTIN in HSTCTL |  |  |  |  |  |  |  |  |  |  |  |  | 3 | 2 | 5 |
| host sets INTOUT in HSTCTL |  |  |  |  |  |  |  |  |  |  |  |  | 3 | 2 | 5 |
| HSTCTLH NMI=1 written by the 34010 |  |  |  |  | 1 |  |  |  |  |  |  | 2 |  |  | 3 |
| HSTCTLH NMIM=1 written by the 34010 |  |  |  |  | 1 |  |  |  |  |  |  | 2 |  |  | 3 |
| host sets NMI in HSTCTL |  |  |  |  | 1 |  |  |  |  |  |  | 2 |  |  | 3 |
| host sets NMIM in HSTCTL |  |  |  |  | 1 |  |  |  |  |  |  | 2 |  |  | 3 |

### Video, VRAM, refresh, cache

| | Z/Y-unit (9) | T-unit (5) | W-unit (6) | Atari GSP (7) | Exterminator (2) | ICE (5) | Cool Pool (3) | Tickee (6) | Skimaxx (1) | X the Ball (1) | Micro3D (3) | JPM Impact (3) | Art & Magic (3) | Inder (3) | all |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| DUDATE=4 | 9 | 5 | 6 | 5 | 2 | 5 |  | 6 |  | 1 |  | 3 |  | 3 | 45 |
| SRT=1 (VRAM shift-register transfers) | 9 | 5 | 6 | 7 | 2 |  | 3 | 2 |  | 1 |  | 3 | 3 | 3 | 44 |
| CAS-before-RAS refresh (RM=1) |  | 5 | 6 | 2 | 2 | 5 | 2 | 6 | 1 |  | 3 | 3 | 2 | 3 | 40 |
| refresh rate RR=0 | 8 | 3 | 4 | 7 |  | 5 | 1 | 5 | 1 |  |  | 3 |  | 3 | 40 |
| refresh rate RR=1 | 4 | 5 | 6 | 7 | 2 |  | 3 | 1 |  | 1 | 3 |  | 3 |  | 35 |
| DUDATE=8 |  |  |  |  |  |  | 2 |  | 1 |  | 3 |  | 3 |  | 9 |
| DUDATE=1 |  |  |  | 7 |  |  |  |  |  |  |  |  |  |  | 7 |
| external sync (DXV=0) written |  |  |  |  | 1 |  |  |  |  |  |  | 3 |  |  | 4 |
| DUDATE=0 |  |  |  |  |  |  |  |  |  |  |  | 3 |  |  | 3 |
| DUDATE=2 |  |  |  | 2 |  |  | 1 |  |  |  |  |  |  |  | 3 |
| HSD=1 written |  |  |  |  |  |  |  |  |  |  |  |  | 3 |  | 3 |
| interlaced video (NIL=0) written |  |  |  |  |  |  |  |  |  |  |  | 3 |  |  | 3 |
| instruction cache disabled (CD=1) |  |  |  |  |  |  |  | 1 |  |  |  |  |  |  | 1 |

### I/O registers the 34010 reads

| | Z/Y-unit (9) | T-unit (5) | W-unit (6) | Atari GSP (7) | Exterminator (2) | ICE (5) | Cool Pool (3) | Tickee (6) | Skimaxx (1) | X the Ball (1) | Micro3D (3) | JPM Impact (3) | Art & Magic (3) | Inder (3) | all |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 34010 reads INTPEND | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 |  | 1 | 3 | 3 |  |  | 50 |
| 34010 reads INTENB | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 5 |  |  | 3 | 3 |  | 1 | 49 |
| 34010 reads DPYCTL | 9 | 5 | 6 | 7 | 2 |  | 3 | 2 |  | 1 | 3 | 3 | 3 | 3 | 47 |
| 34010 reads HCOUNT | 9 | 5 | 6 |  |  |  |  | 4 |  |  |  | 3 |  |  | 27 |
| 34010 reads VCOUNT | 3 | 4 | 4 |  | 2 |  |  | 5 |  | 1 |  | 3 | 3 | 1 | 26 |
| 34010 reads CONTROL |  | 2 | 2 | 7 | 2 |  | 3 | 1 |  | 1 | 3 | 3 |  |  | 24 |
| 34010 reads HSTCTLL |  |  |  | 7 |  |  |  |  |  |  |  | 3 | 3 | 3 | 16 |
| 34010 reads DPYADR |  |  |  | 3 |  |  |  |  |  |  |  | 3 |  |  | 6 |
| 34010 reads REFCNT |  |  |  |  |  |  |  | 1 |  |  |  | 3 | 1 |  | 5 |
| 34010 reads HSTCTLH |  | 1 |  |  |  |  |  |  |  |  |  | 3 |  |  | 4 |
| 34010 reads HSTDATA |  |  |  |  |  |  |  | 1 |  |  |  | 3 |  |  | 4 |
| 34010 reads DPYTAP |  |  |  |  |  |  |  |  |  |  |  | 3 |  |  | 3 |

### Instruction forms executed

| | Z/Y-unit (9) | T-unit (5) | W-unit (6) | Atari GSP (7) | Exterminator (2) | ICE (5) | Cool Pool (3) | Tickee (6) | Skimaxx (1) | X the Ball (1) | Micro3D (3) | JPM Impact (3) | Art & Magic (3) | Inder (3) | all |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ADDK | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| JRcc long | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| JRcc short | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| JRcc short (UC) | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| MOVE @L,Rd,F | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| MOVE Rs,@L,F | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| MOVE Rs,Rd | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| MOVI IL | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| MOVI IW | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| SETF F=0 | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| SETF F=1 | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| SLL K | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 57 |
| ADDI IW | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 56 |
| ANDI | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 2 | 3 | 56 |
| JRcc long (UC) | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 56 |
| MOVE *Rs+,Rd,F | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 56 |
| MOVE *Rs,Rd,F | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 56 |
| MOVE Rs,*Rd+,F | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 56 |
| XOR | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 2 | 56 |
| ADDI IL | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 2 | 55 |
| MOVE Rs,*Rd,F | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 1 | 55 |
| ORI | 9 | 5 | 6 | 7 | 2 | 5 | 2 | 6 | 1 | 1 | 3 | 3 | 2 | 3 | 55 |
| SRL K | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 1 | 55 |
| ADD | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 1 | 54 |
| CALLR | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 |  | 54 |
| CMPI IW | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 2 | 2 | 54 |
| MMFM | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 |  | 54 |
| MOVK | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 |  | 1 | 3 | 3 | 3 | 1 | 54 |
| OR | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 1 | 54 |
| RETS | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 |  | 54 |
| SUBK | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 2 | 2 | 54 |
| MMTM | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 |  | 53 |
| RETI | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 |  | 1 | 3 |  | 3 | 3 | 53 |
| DSJS | 9 | 5 | 6 | 7 | 2 |  | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 3 | 52 |
| CMP | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 5 | 1 | 1 | 3 | 3 | 2 |  | 51 |
| LMO | 9 | 5 | 6 | 7 | 1 |  | 3 | 5 | 1 | 1 | 3 | 3 | 3 | 3 | 50 |
| MOVB *Rs,Rd | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 |  |  | 50 |
| MOVE *Rs(n),Rd,F | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 |  | 1 | 3 | 3 |  |  | 50 |
| MOVE Rs,*Rd(n),F | 9 | 5 | 6 | 7 | 2 | 5 | 3 | 6 |  | 1 | 3 | 3 |  |  | 50 |
| SUB | 9 | 5 | 6 | 7 | 1 | 5 | 3 | 5 | 1 | 1 | 3 | 3 | 1 |  | 50 |
| AND | 9 | 5 | 6 | 6 | 1 | 3 | 3 | 6 |  | 1 | 3 | 3 | 3 |  | 49 |
| DINT | 9 | 5 | 6 |  | 2 | 5 | 3 | 6 | 1 | 1 | 3 | 3 | 3 | 2 | 49 |
| EINT | 9 | 5 | 6 |  | 2 | 5 | 3 | 6 |  | 1 | 3 | 3 | 3 | 3 | 49 |
| MOVE Rs,Rd (other file) | 9 | 5 | 6 | 7 | 2 |  | 3 | 6 | 1 | 1 | 3 | 3 | 3 |  | 49 |
| SUBI IW | 9 | 5 | 6 | 6 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 |  |  | 49 |
| MOVE *Rs+,*Rd+,F | 9 | 5 | 6 | 7 | 2 |  | 3 | 6 |  | 1 | 3 | 3 | 3 |  | 48 |
| NEG | 9 | 5 | 6 | 7 | 1 | 4 | 3 | 2 |  | 1 | 3 | 3 | 3 |  | 47 |
| BTST K | 9 | 5 | 6 | 7 | 1 |  | 3 | 2 |  | 1 | 3 | 3 | 3 | 3 | 46 |
| CMPI IL | 9 | 5 | 6 | 7 | 1 | 3 | 3 | 4 | 1 | 1 | 3 | 3 |  |  | 46 |
| MOVX | 9 | 5 | 6 | 7 | 2 |  | 3 | 2 |  | 1 | 3 | 3 | 3 | 2 | 46 |
| JAcc (UC) | 9 | 5 | 6 | 5 |  | 5 | 3 | 6 | 1 | 1 | 3 |  | 1 |  | 45 |
| MOVE Rs,-*Rd,F | 9 | 5 | 6 | 7 | 1 |  | 3 | 1 |  | 1 | 3 | 3 | 3 | 3 | 45 |
| MOVB Rs,*Rd | 9 | 5 | 6 | 1 | 1 | 5 | 3 | 6 | 1 | 1 | 3 | 3 |  |  | 44 |
| MPYU | 9 | 5 | 6 | 7 | 1 |  | 3 | 5 |  | 1 | 3 | 3 | 1 |  | 44 |
| PUSHST | 9 | 5 | 6 | 7 | 1 | 5 | 2 | 6 | 1 |  |  | 2 |  |  | 44 |
| SRA K | 8 | 5 | 6 | 7 | 1 | 2 | 3 | 2 |  | 1 | 3 | 3 | 2 |  | 43 |
| ADDXY | 9 | 5 | 6 | 7 | 1 |  | 3 | 1 |  | 1 | 3 | 3 | 3 |  | 42 |
| MPYS | 8 | 5 | 5 | 7 |  | 3 | 3 | 2 |  | 1 | 3 | 3 | 2 |  | 42 |
| POPST | 9 | 5 | 6 | 7 | 1 | 5 | 2 | 6 | 1 |  |  |  |  |  | 42 |
| RL K | 8 | 5 | 4 | 7 | 1 |  | 3 | 4 |  | 1 | 2 | 3 | 3 | 1 | 42 |
| SUBXY | 9 | 5 | 6 | 7 | 1 |  | 3 | 1 |  | 1 | 3 | 3 | 3 |  | 42 |
| DIVS | 7 | 5 | 6 | 6 | 1 | 3 | 3 | 2 |  | 1 | 2 | 3 | 2 |  | 41 |
| MOVE @L,@L,F | 9 | 5 | 6 | 7 | 1 |  | 2 | 1 |  | 1 | 3 | 3 | 2 | 1 | 41 |
| MOVY | 9 | 5 | 6 | 7 | 1 |  | 3 | 1 |  |  | 3 | 3 | 3 |  | 41 |
| DIVU | 9 | 5 | 6 | 7 | 1 |  | 2 | 2 |  | 1 | 3 | 1 | 3 |  | 40 |
| XORI | 9 | 5 | 6 | 3 | 2 | 5 | 2 | 6 | 1 | 1 |  |  |  |  | 40 |
| ZEXT F=0 | 9 | 5 | 6 | 7 | 1 |  | 2 | 1 |  | 1 | 3 | 3 | 2 |  | 40 |
| JUMP Rs | 9 | 5 | 6 |  | 1 |  | 3 | 2 | 1 | 1 | 3 | 3 | 3 | 2 | 39 |
| PIXBLT B,XY | 9 | 5 | 6 | 7 | 2 |  | 3 |  |  | 1 | 3 | 3 |  |  | 39 |
| SEXT F=0 | 8 | 5 | 6 | 6 | 1 |  | 3 | 1 |  | 1 | 3 | 3 | 2 |  | 39 |
| SUBI IL | 9 | 5 | 6 | 7 | 1 |  | 3 | 3 |  | 1 | 1 | 3 |  |  | 39 |
| CALLA | 9 | 5 | 6 | 7 | 1 |  | 3 | 1 |  |  | 3 | 3 |  |  | 38 |
| NOP | 8 | 4 | 6 |  | 1 | 5 | 3 | 5 | 1 | 1 | 3 |  | 1 |  | 38 |
| CALL Rs | 8 | 5 | 6 | 7 | 1 |  | 3 | 3 |  | 1 | 3 |  |  |  | 37 |
| MOVE *Rs,*Rd,F | 9 | 5 | 6 | 4 | 1 |  | 3 | 1 |  | 1 | 3 | 3 |  |  | 36 |
| PIXT *Rs,Rd | 9 | 5 | 6 | 7 | 2 |  | 2 |  |  | 1 |  |  | 3 | 1 | 36 |
| JAcc | 8 | 5 | 6 | 6 |  |  | 1 | 3 |  |  | 3 |  | 3 |  | 35 |
| MOVE *Rs(n),*Rd(n),F | 8 | 5 | 6 | 6 | 1 |  | 2 | 1 |  |  | 3 | 3 |  |  | 35 |
| CMPXY | 8 | 5 | 6 | 7 | 1 |  | 3 |  |  |  | 1 | 1 | 2 |  | 34 |
| MOVB @L,Rd | 6 | 5 | 6 | 7 | 1 |  | 2 | 6 |  | 1 |  |  |  |  | 34 |
| SLL Rs | 6 | 5 | 6 | 2 | 1 |  | 3 | 5 |  |  | 3 | 3 |  |  | 34 |
| FILL XY | 7 | 3 | 4 | 7 | 2 |  | 3 |  |  | 1 | 3 | 3 |  |  | 33 |
| MOVB Rs,*Rd(n) | 8 | 5 | 6 | 2 | 1 |  | 3 | 5 |  |  |  | 3 |  |  | 33 |
| MOVB Rs,@L | 5 | 3 | 5 | 7 | 1 | 1 | 3 | 6 |  | 1 | 1 |  |  |  | 33 |
| DSJ | 9 | 5 | 6 |  | 1 |  | 3 | 2 |  | 1 | 1 | 2 | 2 |  | 32 |
| MOVB *Rs(n),Rd | 8 | 5 | 6 | 5 | 1 |  | 2 | 2 |  |  |  | 3 |  |  | 32 |
| NOT | 9 | 5 | 6 |  | 1 |  | 3 | 1 |  | 1 | 3 | 3 |  |  | 32 |
| RL Rs | 9 | 5 | 6 | 6 |  |  | 2 |  |  |  | 1 |  | 3 |  | 32 |
| ADDC | 9 | 5 | 5 | 7 |  |  | 3 |  |  | 1 |  |  |  |  | 30 |
| ANDN | 9 | 5 | 6 |  | 1 |  | 3 |  |  |  | 3 | 3 |  |  | 30 |
| ABS | 8 | 5 | 6 |  | 1 |  | 2 |  |  | 1 | 3 | 3 |  |  | 29 |
| MOVB *Rs,*Rd | 4 | 5 | 6 | 1 | 1 |  | 1 | 2 |  | 1 | 3 | 3 |  |  | 27 |
| EXGPC | 9 | 5 | 6 | 4 |  |  | 2 |  |  |  |  |  |  |  | 26 |
| SLA K | 9 | 4 | 5 |  | 1 |  | 2 | 1 |  | 1 |  |  | 3 |  | 26 |
| BTST Rs | 8 | 5 | 6 |  | 1 |  | 1 | 1 |  | 1 |  |  |  |  | 23 |
| MOVE *Rs(n),*Rd+,F | 1 | 1 | 3 | 6 | 1 |  | 3 | 1 |  |  | 3 | 3 |  |  | 22 |
| PUTST | 6 | 3 | 2 | 7 | 1 |  |  |  |  | 1 |  | 2 |  |  | 22 |
| CLRC | 8 | 5 | 6 |  | 1 |  |  |  |  | 1 |  |  |  |  | 21 |
| FILL L |  | 2 | 2 | 7 |  |  | 3 | 1 |  | 1 |  | 2 | 3 |  | 21 |
| PIXBLT L,XY |  |  |  | 7 | 2 |  | 2 |  |  | 1 | 3 | 3 |  | 3 | 21 |
| GETPC | 9 | 5 | 6 |  |  |  |  |  |  |  |  |  |  |  | 20 |
| GETST | 6 | 3 | 2 | 7 | 1 |  |  |  |  | 1 |  |  |  |  | 20 |
| MOVE -*Rs,Rd,F | 4 | 3 | 3 |  | 1 |  | 3 |  |  |  | 3 | 3 |  |  | 20 |
| SETC | 8 | 5 | 6 |  | 1 |  |  |  |  |  |  |  |  |  | 20 |
| SRL Rs | 5 |  | 3 |  | 1 |  | 2 |  |  | 1 | 3 | 2 | 3 |  | 20 |
| MOVE @L,*Rd+,F |  | 2 | 2 | 6 |  |  | 2 | 1 |  |  | 3 | 3 |  |  | 19 |
| PIXT Rs,*Rd.XY | 5 |  |  | 5 |  |  | 2 | 1 |  | 1 | 3 | 2 |  |  | 19 |
| MOVE -*Rs,-*Rd,F | 5 | 4 | 6 | 2 |  |  |  |  |  |  |  |  |  |  | 17 |
| PIXBLT L,L |  |  |  |  | 1 |  | 3 | 6 | 1 | 1 |  | 3 |  | 2 | 17 |
| CVXYL | 6 |  |  |  | 2 |  | 2 | 1 |  | 1 |  | 3 |  |  | 15 |
| DSJNE | 3 |  |  |  | 1 | 2 |  | 4 |  |  | 3 |  |  |  | 13 |
| TRAP | 4 | 3 | 4 |  |  |  | 1 |  |  | 1 |  |  |  |  | 13 |
| CPW |  |  |  |  |  |  | 2 | 1 |  |  | 3 | 3 | 3 |  | 12 |
| MOVB *Rs(n),*Rd(n) | 2 | 1 | 3 |  |  |  | 2 | 1 |  |  |  | 3 |  |  | 12 |
| MOVB @L,@L |  |  |  | 7 |  |  | 2 | 1 |  |  | 1 |  |  |  | 11 |
| ZEXT F=1 |  |  |  |  |  |  | 2 |  |  |  | 3 | 3 | 3 |  | 11 |
| DRAV | 6 |  |  | 1 | 1 |  | 2 |  |  |  |  |  |  |  | 10 |
| EXGF F=0 | 6 |  |  |  |  |  | 1 |  |  |  |  | 3 |  |  | 10 |
| LINE |  |  |  | 7 |  |  | 1 |  |  |  | 2 |  |  |  | 10 |
| MODS |  |  |  | 2 |  |  | 2 | 1 |  |  | 1 | 3 |  |  | 9 |
| MODU | 2 | 1 | 5 |  |  |  |  |  |  |  | 1 |  |  |  | 9 |
| EXGF F=1 | 6 |  |  |  |  |  |  |  |  |  |  | 2 |  |  | 8 |
| PIXT Rs,*Rd |  |  |  | 7 |  |  |  |  |  |  |  |  |  | 1 | 8 |
| DSJEQ |  |  | 1 | 3 |  |  | 3 |  |  |  |  |  |  |  | 7 |
| SEXT F=1 | 1 | 1 |  |  |  |  |  | 1 |  |  |  | 3 |  |  | 6 |
| PIXBLT XY,L |  |  |  |  |  |  |  |  |  | 1 | 3 |  |  |  | 4 |
| SRA Rs | 1 |  | 1 |  |  |  | 1 |  |  | 1 |  |  |  |  | 4 |
| PIXT *Rs.XY,*Rd.XY |  |  |  | 2 |  |  | 1 |  |  |  |  |  |  |  | 3 |
| PIXT *Rs.XY,Rd |  |  |  |  |  |  | 2 |  |  | 1 |  |  |  |  | 3 |
| REV |  |  |  |  |  |  |  |  |  |  |  | 3 |  |  | 3 |
| SUBB |  |  |  |  |  |  | 2 |  |  |  |  |  |  |  | 2 |
| PIXBLT B,L |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  | 1 |
| PIXBLT XY,XY |  |  |  |  |  |  | 1 |  |  |  |  |  |  |  | 1 |
| PIXT *Rs,*Rd |  |  |  |  |  |  | 1 |  |  |  |  |  |  |  | 1 |

Instruction forms no surveyed game executed: EMU, ILLEGAL (illop), ILLEGAL (unimplemented code), NEGB, SLA Rs
