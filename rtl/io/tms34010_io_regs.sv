// -----------------------------------------------------------------------------
// tms34010_io_regs.sv
//
// On-chip memory-mapped I/O register file for the TMS34010.
//
// Per the 1988 User's Guide Figure 6-1 (page 6-3), the GSP has 32 internal
// 16-bit registers occupying the bit-address range 0xC0000000-0xC00001FF.
// Each register sits at a 0x10-bit-aligned address (16 bits apart). The CPU
// (and, on real silicon, the host) reaches them through the ordinary
// bit-addressed memory interface; an address decodes to I/O space when its
// two MSBs are 11 and bits[29:9] are 0. The register index is addr[8:4].
//
// "All I/O registers ... are cleared to 0 at reset" (UG §6, Reset), except
// HSTCTLH.HLT, which samples HCS at reset release: active-low HCS selects
// self-bootstrap (HLT=0), while inactive-high HCS selects host-present halt.
//
// Current scope (Tasks 0081–0144):
//   - Plain read/write storage for ordinary registers. This is exactly correct
//     for the control/graphics registers that the instruction set reads
//     (PSIZE, PMASK, CONVSP, CONVDP, CONTROL, DPYCTL, ...).
//   - Dedicated taps drive graphics and interrupt control. Sideband inputs
//     auto-clear HSTCTLH.NMI and set the internal interrupt latches.
//   - INTPEND implements the source-specific semantics from pages 6-41/6-42:
//     synchronized read-only external levels, read-only HSTCTLL.INTIN, and
//     hardware-set/write-zero-to-clear DIP/WVP latches.
//   - REFCNT is the live writable refresh counter driven by CONTROL.RR.
//   - HCOUNT/VCOUNT are live writable video counters. Timing registers feed
//     the internal noninterlaced generator; DPYCTL.ENV gates BLANK and DIP.
//   - DPYADR is live display state. DPYSTRT/DPYCTL schedule held
//     screen-refresh requests and update its address/count after acknowledge.
//   - The synchronous four-register host boundary implements HSTADR/HSTDATA
//     indirect sequencing plus per-side HSTCTL ownership, HINT, NMI/HLT
//     control, and HCS-selected reset state. The future pin wrapper owns
//     asynchronous host-bus timing and CDC.
//
// Port shape:
//   - Synchronous active-high reset (assumption A0003); all registers -> 0
//     except HSTCTLH.HLT, which samples hcs_n_i.
//   - One synchronous write port (req & we & is_io).
//   - One combinational (async) read port. The 32x16 array is tiny (512
//     bits) and async read keeps this composable with the core's existing
//     register-style reads; FPGA maps it to flops + a 32:1 mux.
//   - `is_io` tells the caller whether `addr` decoded as I/O space, so the
//     surrounding memory fabric can route reads/writes here vs. external RAM.
//
// Spec source:
//   third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf
//   Figure 6-1 (I/O Register Memory Map), §6 "I/O Registers".
// -----------------------------------------------------------------------------

`default_nettype none
module tms34010_io_regs
  import tms34010_pkg::*;
(
  input  logic                  clk,
  input  logic                  rst,

  // Synchronous four-register host boundary. A later host-bus wrapper
  // converts physical asynchronous pin cycles into this request/ack port.
  input  logic                  hcs_n_i,          // reset strap: 0=run, 1=halt
  input  logic                  host_req_i,
  input  logic                  host_we_i,
  input  host_reg_sel_t         host_reg_i,
  input  logic [1:0]            host_be_i,
  input  local_word_t           host_wdata_i,
  output local_word_t           host_rdata_o,
  output logic                  host_ack_o,
  output logic                  host_busy_o,
  output logic                  hint_n_o,
  output logic                  hlt_o,

  // Held host-indirect local-word client. The future memory arbiter grants
  // and acknowledges this alongside CPU, display, and refresh clients.
  output logic                  host_mem_req_o,
  output logic                  host_mem_we_o,
  output logic [ADDR_WIDTH-1:0] host_mem_addr_o,
  output local_word_t           host_mem_wdata_o,
  input  local_word_t           host_mem_rdata_i,
  input  logic                  host_mem_ack_i,

  input  logic                  req,      // access strobe
  input  logic                  we,       // 1 = write, 0 = read
  input  logic [ADDR_WIDTH-1:0] addr,     // full 32-bit bit-address
  input  logic [15:0]           wdata,

  output logic [15:0]           rdata,    // selected register (0 if not I/O)
  output logic                  is_io,    // addr decodes to I/O space

  // Dedicated taps for the graphics datapath (combinational views of the
  // stored registers). More can be added (PMASK/CONTROL) as the graphics ops
  // that need them land.
  output logic [15:0]           psize_o,  // PSIZE: pixel size in bits (1..16)
  output logic [15:0]           convdp_o, // CONVDP: XY->linear dest pitch shift
  output logic [15:0]           convsp_o, // CONVSP: XY->linear source pitch shift
  output logic [15:0]           control_o,// CONTROL: PPOP[14:10], PBV/PBH, W, T(bit5)
  output logic [15:0]           pmask_o,  // PMASK: plane mask (1 bit = plane masked)
  output logic [15:0]           intenb_o, // INTENB: maskable-interrupt enables
  output logic [15:0]           intpend_o,// INTPEND: maskable-interrupt pending bits
  output logic [15:0]           hstctlh_o,// HSTCTLH: host control (NMI/NMIM in bits 8/9)
  output logic [15:0]           refcnt_o, // REFCNT: live interval/row counter
  output logic                  refresh_req_o, // one cycle at RINTVL underflow
  output logic [7:0]            refresh_row_o, // decremented ROWADR for request
  output logic                  refresh_cbr_o, // CONTROL.RM: 1=CAS-before-RAS
  output logic [15:0]           hcount_o, // live horizontal video counter
  output logic [15:0]           vcount_o, // live vertical video counter
  output logic                  video_hsync_o,
  output logic                  video_vsync_o,
  output logic                  video_hblank_o,
  output logic                  video_vblank_o,
  output logic                  video_blank_o,
  output logic [15:0]           dpyadr_o, // live LNCNT/SRFADR state
  output logic                  screen_refresh_req_o, // held until ack
  input  logic                  screen_refresh_ack_i,
  output logic [13:0]           screen_refresh_srfaddr_o,
  output logic [15:0]           screen_refresh_dpytap_o,
  input  logic                  nmi_clear,     // clear HSTCTLH.NMI after NMI entry
  input  logic                  wvp_set,       // synchronous INTPEND.WVP set pulse
  input  logic                  dpyint_set,    // synchronous INTPEND.DIP set pulse
  input  logic                  lint1_n_i,     // asynchronous, active-low LINT1 pin
  input  logic                  lint2_n_i      // asynchronous, active-low LINT2 pin
);

  // I/O-space decode: two MSBs = 11 and bits[29:9] = 0 (range C0000000-
  // C00001FF). The register index is addr[8:4].
  logic [IO_REG_IDX_W-1:0] idx;
  assign is_io = (addr[ADDR_WIDTH-1:ADDR_WIDTH-2] == 2'b11)
              && (addr[ADDR_WIDTH-3:IO_REG_IDX_W+4] == '0);
  assign idx   = addr[IO_REG_IDX_W+3 : 4];

  // Register storage.
  logic [15:0] io_reg [0:IO_REG_COUNT-1];

  logic lint1_n_sync;
  logic lint2_n_sync;
  logic [15:0] intpend_value;
  logic        refcnt_load;
  logic        hcount_load;
  logic        vcount_load;
  logic        dpyadr_load;
  logic        video_hblank_start;
  logic        video_dpyint_pulse;
  logic        host_ctl_we;
  logic [1:0]  host_ctl_be;
  local_word_t host_ctl_wdata;
  local_word_t host_ctl_rdata;
  logic        cpu_host_we;
  host_reg_sel_t cpu_host_reg;
  local_word_t cpu_host_rdata;

  // Map the processor's three memory-mapped host registers onto the same
  // storage owned by tms34010_host_if. HSTCTL remains in io_reg because its
  // per-side field ownership and interrupt effects live in this block.
  always_comb begin
    cpu_host_reg = HOST_REG_HSTDATA;
    unique case (idx)
      IO_IDX_HSTADRL: cpu_host_reg = HOST_REG_HSTADRL;
      IO_IDX_HSTADRH: cpu_host_reg = HOST_REG_HSTADRH;
      IO_IDX_HSTDATA: cpu_host_reg = HOST_REG_HSTDATA;
      default: ;
    endcase
  end

  assign cpu_host_we = req && we && is_io
                    && ((idx == IO_IDX_HSTADRL)
                        || (idx == IO_IDX_HSTADRH)
                        || (idx == IO_IDX_HSTDATA));

  tms34010_host_if u_host_if (
    .clk           (clk),
    .rst           (rst),
    .host_req_i    (host_req_i),
    .host_we_i     (host_we_i),
    .host_reg_i    (host_reg_i),
    .host_be_i     (host_be_i),
    .host_wdata_i  (host_wdata_i),
    .host_rdata_o  (host_rdata_o),
    .host_ack_o    (host_ack_o),
    .host_busy_o   (host_busy_o),
    .ctl_we_o      (host_ctl_we),
    .ctl_be_o      (host_ctl_be),
    .ctl_wdata_o   (host_ctl_wdata),
    .ctl_rdata_i   (host_ctl_rdata),
    .hstctlh_i     (io_reg[IO_IDX_HSTCTLH]),
    .cpu_we_i      (cpu_host_we),
    .cpu_reg_i     (cpu_host_reg),
    .cpu_wdata_i   (wdata),
    .cpu_rdata_o   (cpu_host_rdata),
    .local_req_o   (host_mem_req_o),
    .local_we_o    (host_mem_we_o),
    .local_addr_o  (host_mem_addr_o),
    .local_wdata_o (host_mem_wdata_o),
    .local_rdata_i (host_mem_rdata_i),
    .local_ack_i   (host_mem_ack_i)
  );

  tms34010_sync_bit #(.RESET_VALUE(1'b1)) u_lint1_sync (
    .clk     (clk),
    .rst     (rst),
    .async_i (lint1_n_i),
    .sync_o  (lint1_n_sync)
  );

  tms34010_sync_bit #(.RESET_VALUE(1'b1)) u_lint2_sync (
    .clk     (clk),
    .rst     (rst),
    .async_i (lint2_n_i),
    .sync_o  (lint2_n_sync)
  );

  assign refcnt_load =
      req && we && is_io && (idx == IO_IDX_REFCNT);
  assign hcount_load =
      req && we && is_io && (idx == IO_IDX_HCOUNT);
  assign vcount_load =
      req && we && is_io && (idx == IO_IDX_VCOUNT);
  assign dpyadr_load =
      req && we && is_io && (idx == IO_IDX_DPYADR);

  // REFCNT is owned by the refresh block rather than mirrored in io_reg.
  // CONTROL.RR clocks its continuous interval/row counter, while a processor
  // write loads the full value. The future arbiter consumes request/row/mode.
  tms34010_refresh u_refresh (
    .clk          (clk),
    .rst          (rst),
    .rr           (io_reg[IO_IDX_CONTROL][CTRL_RR_HI:CTRL_RR_LO]),
    .refcnt_load  (refcnt_load),
    .refcnt_wdata (wdata),
    .refcnt       (refcnt_o),
    .refresh_row  (refresh_row_o),
    .refresh_req  (refresh_req_o)
  );

  assign refresh_cbr_o = io_reg[IO_IDX_CONTROL][CTRL_RM_BIT];

  // The project remains single-clock under A0004 at this integration stage.
  // A later video-boundary task will move this instance to VCLK and replace
  // direct counter/config wiring with explicit CDC structures.
  tms34010_video u_video (
    .clk           (clk),
    .rst           (rst),
    .hesync        (io_reg[IO_IDX_HESYNC]),
    .heblnk        (io_reg[IO_IDX_HEBLNK]),
    .hsblnk        (io_reg[IO_IDX_HSBLNK]),
    .htotal        (io_reg[IO_IDX_HTOTAL]),
    .vesync        (io_reg[IO_IDX_VESYNC]),
    .veblnk        (io_reg[IO_IDX_VEBLNK]),
    .vsblnk        (io_reg[IO_IDX_VSBLNK]),
    .vtotal        (io_reg[IO_IDX_VTOTAL]),
    .dpyint        (io_reg[IO_IDX_DPYINT]),
    .display_enable(io_reg[IO_IDX_DPYCTL][DPYCTL_ENV_BIT]),
    .hcount_load   (hcount_load),
    .hcount_wdata  (wdata),
    .vcount_load   (vcount_load),
    .vcount_wdata  (wdata),
    .hcount        (hcount_o),
    .vcount        (vcount_o),
    .hsync         (video_hsync_o),
    .vsync         (video_vsync_o),
    .hblank        (video_hblank_o),
    .vblank        (video_vblank_o),
    .blank         (video_blank_o),
    .hblank_start  (video_hblank_start),
    .dpyint_pulse  (video_dpyint_pulse)
  );

  // Live display address and held screen-refresh client request. The future
  // memory controller maps SRFADR/DPYTAP onto the physical VRAM row/column
  // phases and acknowledges only after the memory-to-register cycle ends.
  tms34010_display_addr u_display_addr (
    .clk             (clk),
    .rst             (rst),
    .hblank_start    (video_hblank_start),
    .vcount          (vcount_o),
    .veblnk          (io_reg[IO_IDX_VEBLNK]),
    .vsblnk          (io_reg[IO_IDX_VSBLNK]),
    .dpystart        (io_reg[IO_IDX_DPYSTRT]),
    .dpyctl          (io_reg[IO_IDX_DPYCTL]),
    .dpytap          (io_reg[IO_IDX_DPYTAP]),
    .dpyadr_load     (dpyadr_load),
    .dpyadr_wdata    (wdata),
    .dpyadr          (dpyadr_o),
    .refresh_req     (screen_refresh_req_o),
    .refresh_ack     (screen_refresh_ack_i),
    .refresh_srfaddr (screen_refresh_srfaddr_o),
    .refresh_dpytap  (screen_refresh_dpytap_o)
  );

  // INTPEND is a composite view, not general storage. External requests and
  // HIP are read-only levels; only the internal DIP/WVP latches use io_reg.
  always_comb begin
    intpend_value = 16'h0000;
    intpend_value[INT_X1_BIT] = ~lint1_n_sync;
    intpend_value[INT_X2_BIT] = ~lint2_n_sync;
    intpend_value[INT_HI_BIT] =
        io_reg[IO_IDX_HSTCTLL][HSTCTL_INTIN_BIT];
    intpend_value[INT_DI_BIT] =
        io_reg[IO_IDX_INTPEND][INT_DI_BIT];
    intpend_value[INT_WV_BIT] =
        io_reg[IO_IDX_INTPEND][INT_WV_BIT];
  end

  // Async read: the selected register, or 0 when the address is not in
  // I/O space (so a non-I/O read contributes nothing to a merged read bus).
  always_comb begin
    rdata = 16'h0000;
    if (is_io) begin
      unique case (idx)
        IO_IDX_INTPEND: rdata = intpend_value;
        IO_IDX_REFCNT:  rdata = refcnt_o;
        IO_IDX_HCOUNT:  rdata = hcount_o;
        IO_IDX_VCOUNT:  rdata = vcount_o;
        IO_IDX_DPYADR:  rdata = dpyadr_o;
        IO_IDX_HSTADRL,
        IO_IDX_HSTADRH,
        IO_IDX_HSTDATA: rdata = cpu_host_rdata;
        default:        rdata = io_reg[idx];
      endcase
    end
  end

  // Dedicated graphics taps.
  assign psize_o   = io_reg[IO_IDX_PSIZE];
  assign convdp_o  = io_reg[IO_IDX_CONVDP];
  assign convsp_o  = io_reg[IO_IDX_CONVSP];
  assign control_o = io_reg[IO_IDX_CONTROL];
  assign pmask_o   = io_reg[IO_IDX_PMASK];
  assign intenb_o  = io_reg[IO_IDX_INTENB];
  assign intpend_o = intpend_value;
  assign hstctlh_o = io_reg[IO_IDX_HSTCTLH];
  assign host_ctl_rdata = {
    io_reg[IO_IDX_HSTCTLH][15:8],
    io_reg[IO_IDX_HSTCTLL][7:0]
  };
  assign hint_n_o = ~io_reg[IO_IDX_HSTCTLL][HSTCTL_INTOUT_BIT];
  assign hlt_o    = io_reg[IO_IDX_HSTCTLH][HSTCTL_HLT_BIT];

  // Synchronous write + reset. The reset loop is bounded (32 iterations) and
  // fully unrollable, so synthesis treats it as parallel resets.
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < IO_REG_COUNT; i++) begin
        io_reg[i] <= 16'h0;
      end
      // HCS is active low: low selects self-bootstrap/run; high selects the
      // host-present state in which vector fetch waits for a host HLT clear.
      io_reg[IO_IDX_HSTCTLH][HSTCTL_HLT_BIT] <= hcs_n_i;
    end else begin
      if (req && we && is_io) begin
        unique case (idx)
          IO_IDX_INTENB: begin
            // Reserved bits read zero and cannot create interrupt sources.
            io_reg[IO_IDX_INTENB] <= wdata & INT_SOURCE_MASK;
          end

          IO_IDX_INTPEND: begin
            // DIP/WVP are cleared only by writing zero. Writing one retains
            // the old latch; X1P/X2P/HIP and reserved bits are read-only.
            io_reg[IO_IDX_INTPEND][INT_DI_BIT] <=
                io_reg[IO_IDX_INTPEND][INT_DI_BIT]
                & wdata[INT_DI_BIT];
            io_reg[IO_IDX_INTPEND][INT_WV_BIT] <=
                io_reg[IO_IDX_INTPEND][INT_WV_BIT]
                & wdata[INT_WV_BIT];
          end

          IO_IDX_HSTCTLL: begin
            // Processor-side HSTCTLL rules (pages 6-36/6-37): MSGIN is
            // read-only, zero clears INTIN, MSGOUT is writable, and one sets
            // INTOUT. Host-side complementary operations land with host_if.
            io_reg[IO_IDX_HSTCTLL][HSTCTL_INTIN_BIT] <=
                io_reg[IO_IDX_HSTCTLL][HSTCTL_INTIN_BIT]
                & wdata[HSTCTL_INTIN_BIT];
            io_reg[IO_IDX_HSTCTLL][6:4] <= wdata[6:4];
            io_reg[IO_IDX_HSTCTLL][HSTCTL_INTOUT_BIT] <=
                io_reg[IO_IDX_HSTCTLL][HSTCTL_INTOUT_BIT]
                | wdata[HSTCTL_INTOUT_BIT];
          end

          IO_IDX_HSTCTLH: begin
            // Both sides may write all seven defined high-byte fields.
            // Reserved bits 10 and 7:0 always remain zero.
            io_reg[IO_IDX_HSTCTLH] <=
                wdata & HSTCTLH_WRITABLE_MASK;
          end

          IO_IDX_HSTADRL, IO_IDX_HSTADRH, IO_IDX_HSTDATA: begin
            // tms34010_host_if owns these registers. cpu_host_we consumes the
            // completed processor write without launching an indirect cycle.
          end

          IO_IDX_REFCNT: begin
            // The refresh submodule owns the live counter. Its parallel-load
            // port consumes this write, so no mirror storage is updated.
          end

          IO_IDX_DPYTAP: begin
            // Bits 14-15 are reserved/not used by the display address path.
            io_reg[IO_IDX_DPYTAP] <= wdata & DPYTAP_MASK;
          end

          IO_IDX_HCOUNT, IO_IDX_VCOUNT, IO_IDX_DPYADR: begin
            // Video/display submodules own these live registers. Their load
            // ports consume processor writes, so no mirror is updated.
          end

          default: io_reg[idx] <= wdata;
        endcase
      end

      // Direct host writes obey the complementary HSTCTL ownership table.
      // Host owns MSGIN, may set INTIN with one, and may clear INTOUT with
      // zero. MSGOUT remains processor-owned.
      if (host_ctl_we && host_ctl_be[0]) begin
        io_reg[IO_IDX_HSTCTLL][2:0] <= host_ctl_wdata[2:0];
        if (host_ctl_wdata[HSTCTL_INTIN_BIT])
          io_reg[IO_IDX_HSTCTLL][HSTCTL_INTIN_BIT] <= 1'b1;
        if (!host_ctl_wdata[HSTCTL_INTOUT_BIT])
          io_reg[IO_IDX_HSTCTLL][HSTCTL_INTOUT_BIT] <= 1'b0;
      end

      // Conflicting simultaneous HSTCTLH writes are unpredictable on the
      // original device. This synchronous boundary chooses host priority.
      if (host_ctl_we && host_ctl_be[1])
        io_reg[IO_IDX_HSTCTLH] <=
            host_ctl_wdata & HSTCTLH_WRITABLE_MASK;

      // Internal set pulses are independent of an unrelated processor write.
      // A set after a same-cycle write-zero clear wins, preventing an
      // interrupt event from being lost at the register boundary.
      if (dpyint_set || video_dpyint_pulse)
        io_reg[IO_IDX_INTPEND][INT_DI_BIT] <= 1'b1;
      if (wvp_set)
        io_reg[IO_IDX_INTPEND][INT_WV_BIT] <= 1'b1;

      // The HSTCTLL arbitration guarantees hazard-free simultaneous access.
      // Producer-side sets win consumer-side clears for both interrupt bits.
      if (req && we && is_io && (idx == IO_IDX_HSTCTLL)
          && wdata[HSTCTL_INTOUT_BIT])
        io_reg[IO_IDX_HSTCTLL][HSTCTL_INTOUT_BIT] <= 1'b1;

      // A same-cycle host or processor high-byte write wins over the
      // automatic NMI clear.
      if (nmi_clear
          && !(req && we && is_io && (idx == IO_IDX_HSTCTLH))
          && !(host_ctl_we && host_ctl_be[1]))
        io_reg[IO_IDX_HSTCTLH][HSTCTL_NMI_BIT] <= 1'b0;
    end
  end

endmodule : tms34010_io_regs

`default_nettype wire
