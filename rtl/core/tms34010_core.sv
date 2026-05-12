// -----------------------------------------------------------------------------
// tms34010_core.sv
//
// Top-level TMS34010 core wrapper. Phase 3 — decode skeleton integrated.
//
// What this module IS, today:
//   - A clocked top-level entity with explicit synchronous active-high reset.
//   - A typed-enum core FSM that fully cycles: CORE_RESET → CORE_FETCH →
//     CORE_DECODE → CORE_EXECUTE → CORE_WRITEBACK → CORE_FETCH (no
//     instruction touches memory in Phase 3, so CORE_MEMORY is unused).
//   - Memory IF that drives `mem_addr` from the PC register and asserts a
//     16-bit fetch in CORE_FETCH. On mem_ack the fetched word is latched
//     into `instr_word_q` and the PC advances by INSTR_WORD_BITS.
//   - A tms34010_decode instance evaluates `instr_word_q` combinationally.
//     Phase 3 skeleton: every encoding is flagged ILLEGAL. Real
//     instruction patterns land starting Task 0011.
//   - Sticky `illegal_opcode_o` observability output: once decode flags an
//     illegal encoding, this latches high. Cleared only by reset.
//
// What this module IS NOT, yet:
//   - No register file, ALU, or status register instantiated here yet.
//     EXECUTE / WRITEBACK are pass-through states. Task 0011 starts wiring
//     the datapath in alongside the first real instruction (likely MOVI).
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

  // Observability for testbenches (Phase 0..3 — may move to an
  // sva/observability bundle later).
  output core_state_t                         state_o,
  output logic [ADDR_WIDTH-1:0]               pc_o,
  output instr_word_t                         instr_word_o,
  output logic                                illegal_opcode_o
);

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
  // Instruction word latch + decoder
  //
  // instr_word_q is latched the cycle the memory acks an instruction
  // fetch. The decoder runs combinationally; consumers see the decoded
  // result from CORE_DECODE onward.
  // ---------------------------------------------------------------------------
  instr_word_t    instr_word_q;
  decoded_instr_t decoded;

  always_ff @(posedge clk) begin
    if (rst) begin
      instr_word_q <= '0;
    end else if (state_q == CORE_FETCH && mem_ack) begin
      instr_word_q <= mem_rdata[INSTR_WORD_WIDTH-1:0];
    end
  end

  tms34010_decode u_decode (
    .instr  (instr_word_q),
    .decoded(decoded)
  );

  // Sticky illegal-opcode latch. Set on the cycle we are in CORE_DECODE
  // with an illegal `decoded`. Cleared only by reset.
  logic illegal_q;
  always_ff @(posedge clk) begin
    if (rst) begin
      illegal_q <= 1'b0;
    end else if (state_q == CORE_DECODE && decoded.illegal) begin
      illegal_q <= 1'b1;
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

      CORE_DECODE: begin
        // Phase 3 skeleton: decoder runs combinationally; we always
        // advance to EXECUTE on the next clock. Future phases may stall
        // here for multi-word fetches (long-immediate forms).
        state_d = CORE_EXECUTE;
      end

      CORE_EXECUTE: begin
        // Phase 3 skeleton: no real datapath. Illegal-opcode latch was
        // already set in the always_ff sticky block above. Advance.
        // Task 0011+ will switch on decoded.iclass here.
        state_d = CORE_WRITEBACK;
      end

      CORE_MEMORY: begin
        // Unused in Phase 3 — no instruction yet reaches this state.
        // Reserved for memory-touching instructions (Phase 4+).
        state_d = CORE_WRITEBACK;
      end

      CORE_WRITEBACK: begin
        state_d = CORE_FETCH;
      end

      default: begin
        // Defensive: any out-of-range encoding goes back to reset.
        state_d = CORE_RESET;
      end
    endcase
  end

  assign state_o          = state_q;
  assign pc_o             = pc_value;
  assign instr_word_o     = instr_word_q;
  assign illegal_opcode_o = illegal_q;

endmodule : tms34010_core
