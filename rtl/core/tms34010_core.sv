// -----------------------------------------------------------------------------
// tms34010_core.sv
//
// Top-level TMS34010 core wrapper. Phase 0 skeleton only.
//
// What this module IS, today:
//   - A clocked top-level entity with explicit synchronous active-high reset.
//   - A typed-enum core FSM with two real transitions: CORE_RESET → CORE_FETCH,
//     and CORE_FETCH → CORE_DECODE on memory ack.
//   - A request/valid memory interface stub. The stub asserts mem_req in
//     CORE_FETCH; address/size are tied to safe defaults until the PC and
//     decode subsystems land.
//   - Observability ports (`state_o`) so testbenches can self-check FSM state
//     without poking internal signals via hierarchical references.
//
// What this module IS NOT, yet:
//   - There is no PC, no register file, no ALU, no decode, no execute.
//     States after CORE_FETCH currently fall back to CORE_FETCH on the next
//     clock — this is the documented skeleton behavior, not a bug.
//   - The smoke test verifies only that the FSM leaves CORE_RESET on the
//     first clock after reset deassertion.
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

  // Observability for testbenches (Phase 0 only — may move to an
  // sva/observability bundle later).
  output core_state_t                         state_o
);

  // Acknowledge that mem_rdata is not consumed in the skeleton. Suppresses
  // unused-port warnings from lint tools without falsely claiming we read it.
  // When decode lands (Phase 3), this is replaced by real consumers.
  logic [DATA_WIDTH-1:0] unused_rdata;
  assign unused_rdata = mem_rdata;

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
    state_d   = state_q;
    mem_req   = 1'b0;
    mem_we    = 1'b0;
    mem_addr  = '0;
    mem_size  = '0;
    mem_wdata = '0;

    unique case (state_q)
      CORE_RESET: begin
        // Unconditional one-cycle transition out of reset.
        state_d = CORE_FETCH;
      end

      CORE_FETCH: begin
        // Architectural instruction word is 16 bits. The PC is not yet
        // implemented; address is tied to 0 in the skeleton.
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = '0;
        mem_size = 6'd16;
        if (mem_ack) begin
          state_d = CORE_DECODE;
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

endmodule : tms34010_core
