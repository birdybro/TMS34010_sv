// -----------------------------------------------------------------------------
// tb_status_decode.sv
//
// Exhaustive static N/C/Z/V decode audit (Task 0135). Every 16-bit opcode is
// presented to the combinational decoder. For every implemented instruction,
// wb_flags_en and wb_flag_mask must match the instruction-family policy below.
// Runtime qualifications (MOD Rs=0 and graphics CONTROL.W) are deliberately
// exercised by their core-level testbenches rather than this static table.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_status_decode;
  import tms34010_pkg::*;

  instr_word_t   instr;
  decoded_instr_t decoded;
  int unsigned   failures;
  int unsigned   legal_count;
  int unsigned   flag_count;

  tms34010_decode u_decode (
    .instr  (instr),
    .decoded(decoded)
  );

  function automatic alu_flags_t expected_mask(input decoded_instr_t d);
    alu_flags_t result;
    begin
      result = '{n: 1'b0, c: 1'b0, z: 1'b0, v: 1'b0};
      case (d.iclass)
        // Full N/C/Z/V arithmetic and XY comparisons.
        INSTR_ADD_RR, INSTR_SUB_RR, INSTR_CMP_RR,
        INSTR_ADDC_RR, INSTR_SUBB_RR,
        INSTR_ADDK, INSTR_SUBK,
        INSTR_ADDI_IW, INSTR_SUBI_IW, INSTR_CMPI_IW,
        INSTR_ADDI_IL, INSTR_SUBI_IL, INSTR_CMPI_IL,
        INSTR_NEG, INSTR_NEGB,
        INSTR_SLA_K, INSTR_SLA_RR,
        INSTR_ADDXY, INSTR_SUBXY, INSTR_CMPXY:
          result = '{n: 1'b1, c: 1'b1, z: 1'b1, v: 1'b1};

        // Move/absolute-value implicit compare: N/Z plus defined V=0.
        INSTR_MOVI_IW, INSTR_MOVI_IL, INSTR_MOVE_RR, INSTR_ABS:
          result = '{n: 1'b1, c: 1'b0, z: 1'b1, v: 1'b1};

        // Load classes are ordinary N/Z/V loads unless force_pixel marks
        // PIXT, whose instruction page defines only V.
        INSTR_MOVE_FIELD_LOAD, INSTR_MOVE_OFF_LOAD, INSTR_MOVE_ABS_LOAD:
          result = d.force_pixel
                 ? '{n: 1'b0, c: 1'b0, z: 1'b0, v: 1'b1}
                 : '{n: 1'b1, c: 1'b0, z: 1'b1, v: 1'b1};

        // Signed multiply / sign extension.
        INSTR_MPYS, INSTR_SEXT:
          result = '{n: 1'b1, c: 1'b0, z: 1'b1, v: 1'b0};

        // Logical, bit-test, LMO, zero extension, and unsigned multiply.
        INSTR_AND_RR, INSTR_ANDN_RR, INSTR_OR_RR, INSTR_XOR_RR,
        INSTR_ANDI_IL, INSTR_ORI_IL, INSTR_XORI_IL,
        INSTR_NOT, INSTR_BTST_K, INSTR_BTST_RR,
        INSTR_LMO_RR, INSTR_ZEXT, INSTR_MPYU:
          result = '{n: 1'b0, c: 1'b0, z: 1'b1, v: 1'b0};

        // Non-arithmetic shifts/rotate: C and Z only.
        INSTR_SLL_K, INSTR_SRL_K, INSTR_RL_K,
        INSTR_SLL_RR, INSTR_SRL_RR, INSTR_RL_RR:
          result = '{n: 1'b0, c: 1'b1, z: 1'b1, v: 1'b0};

        // Arithmetic right shift: N/C/Z.
        INSTR_SRA_K, INSTR_SRA_RR:
          result = '{n: 1'b1, c: 1'b1, z: 1'b1, v: 1'b0};

        // Divide/modulo families.
        INSTR_DIVU, INSTR_MODU, INSTR_MODS:
          result = '{n: 1'b0, c: 1'b0, z: 1'b1, v: 1'b1};
        INSTR_DIVS:
          result = '{n: 1'b1, c: 1'b0, z: 1'b1, v: 1'b1};

        // Single-purpose flag writers.
        INSTR_CPW:
          result = '{n: 1'b0, c: 1'b0, z: 1'b0, v: 1'b1};
        INSTR_MMTM:
          result = '{n: 1'b1, c: 1'b0, z: 1'b0, v: 1'b0};
        INSTR_CLRC, INSTR_SETC:
          result = '{n: 1'b0, c: 1'b1, z: 1'b0, v: 1'b0};
        default: ;
      endcase
      expected_mask = result;
    end
  endfunction

  initial begin : main
    int unsigned opcode;
    alu_flags_t expected;

    failures = 0;
    legal_count = 0;
    flag_count = 0;

    for (opcode = 0; opcode < 65536; opcode++) begin
      instr = instr_word_t'(opcode);
      #1;
      expected = expected_mask(decoded);

      if (!decoded.illegal) legal_count++;
      if (decoded.wb_flags_en) flag_count++;

      if (decoded.wb_flags_en !== (|expected)) begin
        $display("TEST_RESULT: FAIL: opcode=%04h class=%0d flag_en expected=%0b actual=%0b",
                 instr, decoded.iclass, |expected, decoded.wb_flags_en);
        failures++;
      end
      if ((|expected) && (decoded.wb_flag_mask !== expected)) begin
        $display("TEST_RESULT: FAIL: opcode=%04h class=%0d mask expected=%04b actual=%04b",
                 instr, decoded.iclass, expected, decoded.wb_flag_mask);
        failures++;
      end
    end

    if (legal_count == 0 || flag_count == 0) begin
      $display("TEST_RESULT: FAIL: empty decode sweep legal=%0d flag=%0d",
               legal_count, flag_count);
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (all 65536 opcodes match static NCZV family policy; legal=%0d flag-writing=%0d)",
               legal_count, flag_count);
    else
      $display("TEST_RESULT: FAIL: %0d decode-policy mismatch(es)", failures);
    $finish;
  end
endmodule : tb_status_decode
