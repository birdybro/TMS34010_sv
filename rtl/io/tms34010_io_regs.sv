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
// "All I/O registers ... are cleared to 0 at reset" (UG §6, Reset). The one
// documented exception concerns the HLT bit's dependence on the HCS pin of
// the host interface, which this FPGA reimplementation does not yet model;
// resetting every register to 0 is therefore correct here.
//
// Current scope (Tasks 0081–0137):
//   - Plain read/write storage for ordinary registers. This is exactly correct
//     for the control/graphics registers that the instruction set reads
//     (PSIZE, PMASK, CONVSP, CONVDP, CONTROL, DPYCTL, ...).
//   - Dedicated taps drive graphics and interrupt control. Sideband inputs
//     auto-clear HSTCTLH.NMI and set the internal interrupt latches.
//   - INTPEND implements the source-specific semantics from pages 6-41/6-42:
//     synchronized read-only external levels, read-only HSTCTLL.INTIN, and
//     hardware-set/write-zero-to-clear DIP/WVP latches.
//   - HCOUNT/VCOUNT/REFCNT/DPYADR remain ordinary storage until their
//     video/refresh producers are integrated.
//
// Port shape:
//   - Synchronous active-high reset (assumption A0003), all registers -> 0.
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
  input  logic                  nmi_clear,     // clear HSTCTLH.NMI after NMI entry
  input  logic                  wvp_set,       // synchronous INTPEND.WVP set pulse
  input  logic                  dpyint_set,    // synchronous INTPEND.DIP set pulse
  input  logic                  host_int_set,  // synchronous HSTCTLL.INTIN set pulse
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
      if (idx == IO_IDX_INTPEND)
        rdata = intpend_value;
      else
        rdata = io_reg[idx];
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

  // Synchronous write + reset. The reset loop is bounded (32 iterations) and
  // fully unrollable, so synthesis treats it as parallel resets.
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < IO_REG_COUNT; i++) begin
        io_reg[i] <= 16'h0;
      end
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

          default: io_reg[idx] <= wdata;
        endcase
      end

      // Internal/host set pulses are independent of an unrelated processor
      // write. A set after a same-cycle write-zero clear wins, preventing an
      // interrupt event from being lost at the register boundary.
      if (dpyint_set)
        io_reg[IO_IDX_INTPEND][INT_DI_BIT] <= 1'b1;
      if (wvp_set)
        io_reg[IO_IDX_INTPEND][INT_WV_BIT] <= 1'b1;
      if (host_int_set)
        io_reg[IO_IDX_HSTCTLL][HSTCTL_INTIN_BIT] <= 1'b1;

      // Retain the existing precedence for a simultaneous processor write to
      // HSTCTLH; otherwise interrupt entry automatically clears NMI.
      if (nmi_clear
          && !(req && we && is_io && (idx == IO_IDX_HSTCTLH)))
        io_reg[IO_IDX_HSTCTLH][HSTCTL_NMI_BIT] <= 1'b0;
    end
  end

endmodule : tms34010_io_regs

`default_nettype wire
