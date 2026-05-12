// -----------------------------------------------------------------------------
// tms34010_decode.sv
//
// Phase 3 skeleton: purely combinational instruction decoder.
//
// What it produces:
//   A `decoded_instr_t` summarizing what kind of instruction the input
//   16-bit word is. The Phase 3 skeleton always reports `illegal = 1` and
//   `iclass = INSTR_ILLEGAL` because no SPVU004 opcode-chart rows are
//   populated yet — that work begins in Task 0011 with one instruction per
//   task, each citing the chart row.
//
// Why a separate module:
//   Decode will grow into a substantial pattern-match table (see
//   bibliography/hdl-reimplementation/02-instruction-set.md §"Encoding
//   shape": "The decode space is dense — there is no easy top-bits-give-
//   class partition. Use the SPVU004 opcode chart..."). Isolating it lets
//   the core integrate it cleanly today and lets the decoder grow in its
//   own file.
//
// Synthesis notes:
//   - Purely combinational.
//   - One `always_comb` with safe defaults.
//   - No `/`, no `%`, no loops, no `initial`.
//
// Spec sources:
//   third_party/TMS34010_Info/bibliography/hdl-reimplementation/
//     02-instruction-set.md
//     03-registers.md (operand-field conventions)
// -----------------------------------------------------------------------------

module tms34010_decode
  import tms34010_pkg::*;
(
  input  instr_word_t    instr,
  output decoded_instr_t decoded
);

  // Suppress unused-input warning until real decode arms reference instr.
  // (Phase 3 skeleton ignores it; Task 0011 onwards starts pattern-
  // matching on it.)
  logic [INSTR_WORD_WIDTH-1:0] unused_instr;
  assign unused_instr = instr;

  always_comb begin
    decoded.illegal = 1'b1;
    decoded.iclass  = INSTR_ILLEGAL;
  end

endmodule : tms34010_decode
