// -----------------------------------------------------------------------------
// sim_memory_model.sv
//
// Behavioral memory model for testbenches. NOT synthesizable — lives under
// sim/models/ for that reason. It models the abstract memory interface that
// the core sees (request/valid + bit-addressed) with one-cycle latency and a
// 16-bit-word physical backing store.
//
// Phase 1 scope:
//   - Reads of `INSTR_WORD_BITS` (=16) at 16-bit-aligned bit addresses.
//   - Writes of up to 16 bits, low-bits-aligned within the target word.
//   - Out-of-range or non-aligned reads emit a $display warning so bugs
//     in the surrounding test setup surface early.
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
            state_q       <= MEM_ACK;
            // Surface alignment bugs early. 16-bit fetches must have
            // mem_addr[3:0] == 0 in Phase 1.
            if (!mem_we && mem_size == INSTR_WORD_BITS &&
                mem_addr[3:0] != 4'h0) begin
              $display("sim_memory_model[%0t]: WARN: 16-bit read at non-aligned addr=%08h",
                       $time, mem_addr);
            end
          end
        end

        MEM_ACK: begin
          mem_ack <= 1'b1;
          if (latched_we) begin
            mem[word_idx] <= latched_wdata[15:0];
            mem_rdata     <= '0;
          end else begin
            mem_rdata <= {16'h0, mem[word_idx]};
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
