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
// Scope (Task 0081 — foundation):
//   - Plain read/write storage for all 32 registers. This is exactly correct
//     for the control/graphics registers that the instruction set reads
//     (PSIZE, PMASK, CONVSP, CONVDP, CONTROL, DPYCTL, ...).
//   - Registers whose real silicon behavior is read-only or has write side
//     effects (HCOUNT/VCOUNT/REFCNT/DPYADR are driven by video timing;
//     INTPEND bits are write-to-clear) are MODELLED AS PLAIN STORAGE for now.
//     Those side effects arrive with the video-timing and interrupt blocks
//     (see docs/memory_map.md). No instruction implemented so far depends on
//     them.
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
  input  logic                  nmi_clear,// 1-cycle: clear HSTCTLH.NMI (device took NMI)
  input  logic                  wvp_set   // 1-cycle: set INTPEND.WV (window violation)
);

  // I/O-space decode: two MSBs = 11 and bits[29:9] = 0 (range C0000000-
  // C00001FF). The register index is addr[8:4].
  logic [IO_REG_IDX_W-1:0] idx;
  assign is_io = (addr[ADDR_WIDTH-1:ADDR_WIDTH-2] == 2'b11)
              && (addr[ADDR_WIDTH-3:IO_REG_IDX_W+4] == '0);
  assign idx   = addr[IO_REG_IDX_W+3 : 4];

  // Register storage.
  logic [15:0] io_reg [0:IO_REG_COUNT-1];

  // Async read: the selected register, or 0 when the address is not in
  // I/O space (so a non-I/O read contributes nothing to a merged read bus).
  assign rdata = is_io ? io_reg[idx] : 16'h0;

  // Dedicated graphics taps.
  assign psize_o   = io_reg[IO_IDX_PSIZE];
  assign convdp_o  = io_reg[IO_IDX_CONVDP];
  assign convsp_o  = io_reg[IO_IDX_CONVSP];
  assign control_o = io_reg[IO_IDX_CONTROL];
  assign pmask_o   = io_reg[IO_IDX_PMASK];
  assign intenb_o  = io_reg[IO_IDX_INTENB];
  assign intpend_o = io_reg[IO_IDX_INTPEND];
  assign hstctlh_o = io_reg[IO_IDX_HSTCTLH];

  // Synchronous write + reset. The reset loop is bounded (32 iterations) and
  // fully unrollable, so synthesis treats it as parallel resets.
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < IO_REG_COUNT; i++) begin
        io_reg[i] <= 16'h0;
      end
    end else if (req && we && is_io) begin
      io_reg[idx] <= wdata;
    end else if (nmi_clear) begin
      // The device automatically clears HSTCTLH.NMI when it takes the NMI
      // (1988 UG §8). A normal I/O write takes precedence (the else-if order):
      // simultaneous host write + take is a don't-care corner.
      io_reg[IO_IDX_HSTCTLH][HSTCTL_NMI_BIT] <= 1'b0;
    end else if (wvp_set) begin
      // The graphics engine sets INTPEND.WV on a window violation (1988 UG
      // §7.10). Like nmi_clear, this is a device-internal set, lower priority
      // than a host/program I/O write.
      io_reg[IO_IDX_INTPEND][INT_WV_BIT] <= 1'b1;
    end
  end

endmodule : tms34010_io_regs

`default_nettype wire
