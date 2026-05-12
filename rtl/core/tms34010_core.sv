// -----------------------------------------------------------------------------
// tms34010_core.sv
//
// Top-level TMS34010 core wrapper. Phase 1 — PC integrated.
//
// What this module IS, today:
//   - A clocked top-level entity with explicit synchronous active-high reset.
//   - A typed-enum core FSM with two real transitions: CORE_RESET → CORE_FETCH,
//     and CORE_FETCH → CORE_DECODE on memory ack.
//   - A request/valid memory interface stub. `mem_addr` is driven from
//     the PC register. PC advances by `INSTR_WORD_BITS` (=16 bits) on
//     every `mem_ack` arriving in CORE_FETCH.
//   - Observability ports (`state_o`, `pc_o`) so testbenches can self-check
//     FSM and PC state without poking internal signals via hierarchical
//     references.
//
// What this module IS NOT, yet:
//   - There is no register file, no ALU, no decode, no execute.
//     States after CORE_FETCH currently fall back to CORE_FETCH on the next
//     clock — this is the documented skeleton behavior, not a bug.
//   - No branches / jumps yet, so the PC `load_en` port is tied 0.
//   - The PC starts at `RESET_PC` from the package, currently a placeholder
//     '0 — see docs/assumptions.md A0008 for the architectural reset-vector
//     fetch sequence that is Phase 8 work.
//
// Synthesis notes:
//   - One sequential `always_ff` for the state register.
//   - One `always_comb` for next-state and combinational outputs, with safe
//     defaults at the top to prevent latch inference.
//   - No `/`, `%`, runtime loops, or `initial` blocks.
//   - Reset is synchronous active-high (project convention A0003).
//
// Spec source: third_party/TMS34010_Info/docs/ti-official/
//              1988_TI_TMS34010_Users_Guide.pdf
// -----------------------------------------------------------------------------

module tms34010_core
  import tms34010_pkg::*;
(
  input  logic                                clk,
  input  logic                                rst,

  // Memory request/valid interface (stub in Phase 0 skeleton).
  output logic                                mem_req,
  output logic                                mem_we,
  output logic [ADDR_WIDTH-1:0]               mem_addr,
  output logic [FIELD_SIZE_WIDTH-1:0]         mem_size,
  output logic [DATA_WIDTH-1:0]               mem_wdata,
  input  logic [DATA_WIDTH-1:0]               mem_rdata,
  input  logic                                mem_ack,

  // Observability for testbenches (Phase 0/1 only — may move to an
  // sva/observability bundle later).
  output core_state_t                         state_o,
  output logic [ADDR_WIDTH-1:0]               pc_o
);

  // Acknowledge that mem_rdata is not consumed in the skeleton. Suppresses
  // unused-port warnings from lint tools without falsely claiming we read it.
  // When decode lands (Phase 3), this is replaced by real consumers.
  logic [DATA_WIDTH-1:0] unused_rdata;
  assign unused_rdata = mem_rdata;

  // ---------------------------------------------------------------------------
  // Program counter
  // ---------------------------------------------------------------------------
  logic                  pc_advance_en;
  logic [ADDR_WIDTH-1:0] pc_value;

  tms34010_pc u_pc (
    .clk            (clk),
    .rst            (rst),
    .load_en        (1'b0),               // no branches yet (Phase 4)
    .load_value     ('0),
    .advance_en     (pc_advance_en),
    .advance_amount (PC_ADVANCE_WIDTH'(INSTR_WORD_BITS)),
    .pc_o           (pc_value)
  );

  // ---------------------------------------------------------------------------
  // State register
  // ---------------------------------------------------------------------------
  core_state_t state_q;
  core_state_t state_d;

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= CORE_RESET;
    end else begin
      state_q <= state_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Next-state + combinational outputs
  //
  // Safe defaults at the top — none of the output muxes can infer a latch.
  // ---------------------------------------------------------------------------
  always_comb begin
    // Defaults.
    state_d       = state_q;
    mem_req       = 1'b0;
    mem_we        = 1'b0;
    mem_addr      = '0;
    mem_size      = '0;
    mem_wdata     = '0;
    pc_advance_en = 1'b0;

    unique case (state_q)
      CORE_RESET: begin
        // Unconditional one-cycle transition out of reset.
        state_d = CORE_FETCH;
      end

      CORE_FETCH: begin
        // Architectural instruction word is 16 bits. Fetch from PC.
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = pc_value;
        mem_size = INSTR_WORD_BITS;
        if (mem_ack) begin
          state_d       = CORE_DECODE;
          pc_advance_en = 1'b1;       // advance PC by INSTR_WORD_BITS
        end
      end

      CORE_DECODE,
      CORE_EXECUTE,
      CORE_MEMORY,
      CORE_WRITEBACK: begin
        // TODO Phase 3+: real decode/execute/memory/writeback datapaths.
        // Skeleton placeholder: return to fetch so the FSM remains live
        // for waveform/observability tests, but never produces side effects.
        state_d = CORE_FETCH;
      end

      default: begin
        // Defensive: any out-of-range encoding goes back to reset.
        state_d = CORE_RESET;
      end
    endcase
  end

  assign state_o = state_q;
  assign pc_o    = pc_value;

endmodule : tms34010_core
