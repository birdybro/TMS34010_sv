// -----------------------------------------------------------------------------
// sim_memory_model.sv
//
// Behavioral memory model for testbenches. NOT synthesizable — lives under
// sim/models/ for that reason. It models the abstract memory interface that
// the core sees (request/valid + bit-addressed) with one-cycle latency and a
// 16-bit-word physical backing store.
//
// Scope:
//   - Bit-field reads and writes of 1..32 bits at ANY bit address. A field
//     may straddle 16-bit word boundaries (it spans at most 3 words); writes
//     are read-modify-write so bits outside the field are preserved. The
//     common aligned 16/32-bit fetches the core issues today are just the
//     boff=0 special cases of this path. Sizes outside 1..32 warn.
//   - Reads return the field zero-extended into the 32-bit data bus; the
//     core applies any FE-driven sign/zero extension on top.
//
// Public API for testbenches:
//   - The internal `mem[0:DEPTH_WORDS-1]` array is exposed (no SV access
//     modifier hides it) and can be poked via hierarchical reference, e.g.
//       u_mem.mem[0] = 16'hF000;
//
// Protocol (must match `tms34010_core` memory IF):
//
//        clk        __/¯¯\__/¯¯\__/¯¯\__/¯¯\__/¯¯\__
//        mem_req    _______/¯¯¯¯¯¯¯¯¯¯\__________   request held until ack
//        mem_ack    ____________/¯¯\______________   one-cycle ack pulse
//        mem_rdata  ............X[data]X.........   valid on the ack cycle
// -----------------------------------------------------------------------------

module sim_memory_model
  import tms34010_pkg::*;
#(
  parameter int unsigned DEPTH_WORDS = 1024  // 1024 x 16-bit = 16 Kbits
)(
  input  logic                              clk,
  input  logic                              rst,

  input  logic                              mem_req,
  input  logic                              mem_we,
  input  logic [ADDR_WIDTH-1:0]             mem_addr,
  input  logic [FIELD_SIZE_WIDTH-1:0]       mem_size,
  input  logic [DATA_WIDTH-1:0]             mem_wdata,

  output logic [DATA_WIDTH-1:0]             mem_rdata,
  output logic                              mem_ack
);

  localparam int unsigned IDX_WIDTH = $clog2(DEPTH_WORDS);

  // Physical backing store.
  logic [15:0] mem [0:DEPTH_WORDS-1];

  // Mini-FSM: accept one request, drive one ack pulse, then idle.
  typedef enum logic [0:0] {
    MEM_IDLE = 1'b0,
    MEM_ACK  = 1'b1
  } mem_state_t;
  mem_state_t state_q;

  logic [ADDR_WIDTH-1:0]       latched_addr;
  logic                        latched_we;
  logic [DATA_WIDTH-1:0]       latched_wdata;
  logic [FIELD_SIZE_WIDTH-1:0] latched_size;

  // Sim-only init: zero the backing store so addresses the testbench
  // hasn't preloaded read back as 0 rather than X. The memory model is
  // not synthesizable, so `initial` is fine here.
  initial begin
    for (int unsigned i = 0; i < DEPTH_WORDS; i++) begin
      mem[i] = '0;
    end
  end

  // Bit-address [3:0] = within-word bit offset (must be 0 for the
  // Phase 1 16-bit-aligned fetch path).
  // Bit-address [IDX_WIDTH+3:4] = word index.
  logic [IDX_WIDTH-1:0] word_idx;
  assign word_idx = latched_addr[IDX_WIDTH+3 : 4];

  // Plain `always` (not `always_ff`) so `mem` can also be driven by the
  // sim-only `initial` block above without violating SV-2009's "one
  // driving process per variable" rule for always_ff. This file is
  // intentionally not synthesizable.
  always @(posedge clk) begin
    if (rst) begin
      state_q   <= MEM_IDLE;
      mem_ack   <= 1'b0;
      mem_rdata <= '0;
    end else begin
      unique case (state_q)
        MEM_IDLE: begin
          mem_ack <= 1'b0;
          // Wait for the previous ack pulse to fully clear before
          // accepting a new request. Without this guard the memory
          // would re-latch on the cycle the ack is being driven
          // (the producer's mem_req only falls one cycle AFTER it
          // observes the ack), giving a one-fetch lag in mem_rdata.
          if (mem_req && !mem_ack) begin
            latched_addr  <= mem_addr;
            latched_we    <= mem_we;
            latched_wdata <= mem_wdata;
            latched_size  <= mem_size;
            state_q       <= MEM_ACK;
            // Field accesses may be 1..32 bits at ANY bit address (the
            // generalized RMW path below handles fields that straddle
            // 16-bit word boundaries). Only invalid sizes warn now.
            if (mem_size == 6'd0 || mem_size > 6'd32) begin
              $display("sim_memory_model[%0t]: WARN: field size %0d out of range (1..32)",
                       $time, mem_size);
            end
          end
        end

        MEM_ACK: begin : ack_blk
          // Generalized bit-field access. The backing store is a flat
          // little-endian bit stream: global bit B is mem[B>>4][B&15].
          // A field of `sz` bits (1..32) at bit offset `boff` (0..15)
          // within word `widx` occupies at most 3 consecutive words
          // (15 + 32 = 47 bits < 48). We read that 48-bit window,
          // extract (read) or splice-and-write-back (RMW write) the
          // field, touching only the words it actually spans.
          //
          // `automatic` is required so the initializers re-evaluate on
          // every clock (static procedural vars init only once, at t=0).
          automatic int unsigned widx = int'(word_idx);
          automatic int unsigned boff = int'(latched_addr[3:0]);
          automatic int unsigned sz   = int'(latched_size);
          automatic logic [15:0] r0 = (widx     < DEPTH_WORDS) ? mem[widx]     : 16'h0;
          automatic logic [15:0] r1 = (widx + 1 < DEPTH_WORDS) ? mem[widx + 1] : 16'h0;
          automatic logic [15:0] r2 = (widx + 2 < DEPTH_WORDS) ? mem[widx + 2] : 16'h0;
          automatic logic [47:0] win   = {r2, r1, r0};
          automatic logic [47:0] rmask = (48'd1 << sz) - 48'd1;          // sz low bits
          automatic logic [47:0] smask = rmask << boff;                  // field in place
          automatic int unsigned last  = boff + sz - 1;                  // top bit, <= 46
          automatic logic [47:0] merged;
          mem_ack <= 1'b1;
          if (latched_we) begin
            merged = (win & ~smask) | (({16'h0, latched_wdata} << boff) & smask);
            if (widx     < DEPTH_WORDS)              mem[widx]     <= merged[15:0];
            if (last >= 16 && widx + 1 < DEPTH_WORDS) mem[widx + 1] <= merged[31:16];
            if (last >= 32 && widx + 2 < DEPTH_WORDS) mem[widx + 2] <= merged[47:32];
            mem_rdata <= '0;
          end else begin
            // Extract the field, zero-extended into the 32-bit return.
            // The core applies FE-driven sign/zero extension on top.
            mem_rdata <= 32'((win >> boff) & rmask);
          end
          state_q <= MEM_IDLE;
        end

        default: begin
          state_q <= MEM_IDLE;
          mem_ack <= 1'b0;
        end
      endcase
    end
  end

endmodule : sim_memory_model
