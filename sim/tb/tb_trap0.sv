// -----------------------------------------------------------------------------
// tb_trap0.sv
//
// TRAP 0 — the special-cased level-0 software trap. Per SPVU001A page
// 12-253 note 1: "The level 0 trap differs from all other traps; it
// does not save the old status register or program counter. This may
// be useful in cases where the stack pointer is corrupted or
// uninitialised."
//
// Semantics for N=0:
//   1) ST <- 0x00000010   (same as any TRAP)
//   2) PC <- mem[0xFFFFFFE0]
// SP is NOT decremented; no PC' or ST is pushed.
//
// Test plan:
//   - Pre-load SP with a recognisable value (0x0000_0800) and pre-
//     place sentinel values at SP-32 and SP-64 in memory. After
//     TRAP 0, the sentinels MUST be untouched — that proves the
//     pushes were genuinely skipped (not just landed elsewhere).
//   - After reset has used the level-0 vector to boot at zero, replace the
//     memory model's dedicated level-0 vector with the service address.
//   - Pre-place a service routine at word 100 that writes A6 and
//     halts.
//   - Execute TRAP 0.
//   - Verify: SP unchanged, ST = 0x10, A6 = sentinel, sentinel
//     memory locations untouched.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_trap0;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req;
  logic                          mem_we;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata;
  logic [DATA_WIDTH-1:0]         mem_rdata;
  logic                          mem_ack;
  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  tms34010_core u_core (
    .clk             (clk),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(1024)) u_mem (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ack  (mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual,
                           input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_word(input string label,
                            input logic [15:0] actual,
                            input logic [15:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%04h actual=%04h",
               label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [DATA_WIDTH-1:0] SP_INIT    = 32'h0000_0800;
  localparam logic [DATA_WIDTH-1:0] SERVICE_PC = 32'h0000_0640;  // word 100

  // Sentinel pattern words pre-placed at the would-be push slots
  // (mem[SP-32 ..SP-1] and mem[SP-64..SP-33]). If TRAP 0 wrongly
  // pushed, these would be overwritten.
  localparam logic [15:0] PUSH_PC_LO_SENTINEL = 16'hDEAD;
  localparam logic [15:0] PUSH_PC_HI_SENTINEL = 16'hBEEF;
  localparam logic [15:0] PUSH_ST_LO_SENTINEL = 16'hFEED;
  localparam logic [15:0] PUSH_ST_HI_SENTINEL = 16'hFACE;

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // NOP-fill.
    for (i = 0; i < 1024; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Pre-place service routine at word 100 ------------------------
    // Writes A6 = 0x0BAD_C0DE and halts. We deliberately do NOT RETI
    // back here — the test only cares that the vector fetch and ST
    // overwrite happened, plus that no pushes occurred.
    p = 100;
    p = place_movi_il(p, 4'd6, 32'h0BAD_C0DE);
    u_mem.mem[p] = 16'hC0FF;

    // ---- Pre-place sentinels at the would-be push slots ---------------
    // SP_INIT = bit-addr 0x0800 = word 128.
    // SP-32 = bit-addr 0x07E0 = word 126 (low) + word 127 (high).
    // SP-64 = bit-addr 0x07C0 = word 124 (low) + word 125 (high).
    u_mem.mem[126] = PUSH_PC_LO_SENTINEL;
    u_mem.mem[127] = PUSH_PC_HI_SENTINEL;
    u_mem.mem[124] = PUSH_ST_LO_SENTINEL;
    u_mem.mem[125] = PUSH_ST_HI_SENTINEL;

    // ---- Pre-place pre-TRAP program at word 0 -------------------------
    p = 0;
    // MOVI A2, SP_INIT; MOVE A2, A15 — load SP.
    p = place_movi_il(p, 4'd2, SP_INIT);
    u_mem.mem[p] = 16'h4C4F; p = p + 1;  // MOVE A2, A15
    // MOVI A1, 0xCAFEBABE + PUTST A1 — push a distinguishable ST that
    // we DON'T expect to find at the would-be SP-64 slot (since TRAP 0
    // skips the ST push).
    p = place_movi_il(p, 4'd1, 32'hCAFE_BABE);
    u_mem.mem[p] = 16'h01A0 | 16'h0001; p = p + 1;  // PUTST A1

    // ---- TRAP 0 -------------------------------------------------------
    // Encoding: 0x0900 | 0 = 0x0900.
    u_mem.mem[p] = 16'h0900; p = p + 1;

    repeat (3) @(posedge clk);
    #1;
    rst = 1'b0;

    // The reset transaction used the default vector (0) to reach this
    // program. Once CORE_FETCH begins at zero, retarget the same level-0
    // storage for the later TRAP 0 instruction.
    wait (state_w == CORE_FETCH && pc_w == 32'h0000_0000);
    #1;
    u_mem.level0_vector = SERVICE_PC;

    repeat (2000) @(posedge clk);
    #1;

    // -------- Checks ---------------------------------------------------
    // Service routine ran.
    check_reg("TRAP 0: service routine executed (A6 = 0x0BADC0DE)",
              u_core.u_regfile.a_regs[6], 32'h0BAD_C0DE);

    // SP UNCHANGED — this is the defining property of TRAP 0.
    check_reg("TRAP 0: SP unchanged (no pushes)",
              u_core.u_regfile.sp_q, SP_INIT);

    // ST overwritten to 0x10 (same as any TRAP).
    check_reg("TRAP 0: ST <- 0x00000010",
              u_core.u_status_reg.st_q, 32'h0000_0010);

    // Sentinel slots untouched (no pushes happened).
    check_word("TRAP 0: SP-32 low half untouched",
               u_mem.mem[126], PUSH_PC_LO_SENTINEL);
    check_word("TRAP 0: SP-32 high half untouched",
               u_mem.mem[127], PUSH_PC_HI_SENTINEL);
    check_word("TRAP 0: SP-64 low half untouched",
               u_mem.mem[124], PUSH_ST_LO_SENTINEL);
    check_word("TRAP 0: SP-64 high half untouched",
               u_mem.mem[125], PUSH_ST_HI_SENTINEL);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (TRAP 0: SP unchanged; ST<-0x10; vector fetched; no pushes)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_trap0 hard timeout");
    $fatal(1);
  end

endmodule : tb_trap0
