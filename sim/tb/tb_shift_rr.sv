// -----------------------------------------------------------------------------
// tb_shift_rr.sv
//
// Shift register-register family: SLA / SLL / SRA / SRL / RL with the
// shift amount coming from Rs[4:0]. Per SPVU001A summary table page
// A-15:
//
//   SLA Rs, Rd : 0110 000S SSSR DDDD   (top7 = 7'b0110_000)
//   SLL Rs, Rd : 0110 001S SSSR DDDD   (top7 = 7'b0110_001)
//   SRA Rs, Rd : 0110 010S SSSR DDDD   (top7 = 7'b0110_010)
//   SRL Rs, Rd : 0110 011S SSSR DDDD   (top7 = 7'b0110_011)
//   RL  Rs, Rd : 0110 100S SSSR DDDD   (top7 = 7'b0110_100)
//
// Per A0019 (extended): SRA Rs and SRL Rs interpret Rs[4:0] as the
// 2's complement of the shift magnitude, so the core's shifter-amount
// mux negates Rs[4:0] before driving the shifter.
//
// Scenarios mirror the K-form `tb_shift_k.sv` but read the shift
// amount from a register:
//   - SLL Rs, Rd : shift left logical
//   - SLA Rs, Rd : shift left arithmetic (same data path; V differs)
//   - SRA Rs, Rd : shift right arithmetic (sign-extend); amount is
//                  negated Rs[4:0]
//   - SRL Rs, Rd : shift right logical; amount negated Rs[4:0]
//   - RL  Rs, Rd : rotate left
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_shift_rr;
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

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
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

  // ---------------------------------------------------------------------------
  // Encoding helpers.
  //   shift_rr_enc(top7, Rs, R, Rd) = (top7 << 9) | (Rs << 5) | (R << 4) | Rd
  // For SLA Rs,Rd: top7 = 7'b0110_000 = 0x30, base = 0x6000.
  // For SLL Rs,Rd: top7 = 0x31, base = 0x6200.
  // ...etc.
  // ---------------------------------------------------------------------------
  function automatic instr_word_t shift_rr_enc(input logic [6:0]  top7,
                                               input reg_idx_t    rs,
                                               input reg_file_t   rf,
                                               input reg_idx_t    rd);
    shift_rr_enc = (instr_word_t'(top7) << 9)
                 | (instr_word_t'(rs)   << 5)
                 | (instr_word_t'(rf)   << 4)
                 |  instr_word_t'(rd);
  endfunction

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
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

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // Encoding sanity:
    //   SLL A1, A2 (top7=7'b0110_001 = 0x31, Rs=A1, Rd=A2) =
    //     (0x31 << 9) | (1<<5) | 0 | 2 = 0x6200 | 0x20 | 2 = 0x6222
    if (shift_rr_enc(7'b0110_001, 4'd1, REG_FILE_A, 4'd2) !== 16'h6222) begin
      $display("TEST_RESULT: FAIL: SLL A1,A2 = %04h, expected 6222",
               shift_rr_enc(7'b0110_001, 4'd1, REG_FILE_A, 4'd2));
      failures++;
    end
    //   SRA A3, A4 (top7=7'b0110_010=0x32) = (0x32<<9) | (3<<5) | 4 = 0x6464
    if (shift_rr_enc(7'b0110_010, 4'd3, REG_FILE_A, 4'd4) !== 16'h6464) begin
      $display("TEST_RESULT: FAIL: SRA A3,A4 = %04h, expected 6464",
               shift_rr_enc(7'b0110_010, 4'd3, REG_FILE_A, 4'd4));
      failures++;
    end

    // Pre-fill memory with NOP.
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    p = 0;

    // ---- Setup --------------------------------------------------------
    // A0 holds shift amount = 4 for left/rotate shifts.
    p = place_movi_il(p, REG_FILE_A, 4'd0, 32'd4);
    // A1 holds shift amount for right shifts. Per A0019, the HW takes
    // the 2's complement of A1[4:0] as the magnitude. To shift right by
    // 4, we want HW magnitude = 4, so 2sCmp(A1[4:0]) = 4 → A1[4:0] = -4
    // = 28 (5-bit 2's-comp). 28 = 0x1C.
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'd28);

    // ---- Scenario 1: SLL A0, A2 (shift A2 left by 4) ----------------------
    // A2 starts at 0x0F0F_F0F0; shifted left by 4 → 0xF0FF_0F00.
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'h0F0F_F0F0);
    u_mem.mem[p] = shift_rr_enc(7'b0110_001, 4'd0, REG_FILE_A, 4'd2); p = p + 1;
    // After: A2 = 0xF0FF_0F00.

    // ---- Scenario 2: SLA A0, A3 (same data path, V flag may differ) ------
    // A3 starts at 0x0000_0001; shifted left by 4 → 0x0000_0010.
    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'h0000_0001);
    u_mem.mem[p] = shift_rr_enc(7'b0110_000, 4'd0, REG_FILE_A, 4'd3); p = p + 1;

    // ---- Scenario 3: SRA A1, A4 (sign-extending right shift by 4) --------
    // A4 starts at 0xF000_0000 (sign bit set); SRA by 4 → 0xFF00_0000.
    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'hF000_0000);
    u_mem.mem[p] = shift_rr_enc(7'b0110_010, 4'd1, REG_FILE_A, 4'd4); p = p + 1;

    // ---- Scenario 4: SRL A1, A5 (logical right shift by 4) ----------------
    // A5 starts at 0xF000_0000; SRL by 4 → 0x0F00_0000.
    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'hF000_0000);
    u_mem.mem[p] = shift_rr_enc(7'b0110_011, 4'd1, REG_FILE_A, 4'd5); p = p + 1;

    // ---- Scenario 5: RL A0, A6 (rotate left by 4) -------------------------
    // A6 starts at 0x1234_5678; RL by 4 → 0x2345_6781.
    p = place_movi_il(p, REG_FILE_A, 4'd6, 32'h1234_5678);
    u_mem.mem[p] = shift_rr_enc(7'b0110_100, 4'd0, REG_FILE_A, 4'd6); p = p + 1;

    // Halt
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1500) @(posedge clk);
    #1;

    check_reg("SLL A0(=4),A2: 0x0F0FF0F0 << 4 → 0xF0FF0F00",
              u_core.u_regfile.a_regs[2], 32'hF0FF_0F00);
    check_reg("SLA A0(=4),A3: 0x00000001 << 4 → 0x00000010",
              u_core.u_regfile.a_regs[3], 32'h0000_0010);
    check_reg("SRA A1(=-4),A4: 0xF0000000 >>> 4 → 0xFF000000",
              u_core.u_regfile.a_regs[4], 32'hFF00_0000);
    check_reg("SRL A1(=-4),A5: 0xF0000000 >> 4 → 0x0F000000",
              u_core.u_regfile.a_regs[5], 32'h0F00_0000);
    check_reg("RL A0(=4),A6: 0x12345678 ROL 4 → 0x23456781",
              u_core.u_regfile.a_regs[6], 32'h2345_6781);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (Shift Rs forms: SLA/SLL/SRA/SRL/RL with Rs-supplied amount)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_shift_rr hard timeout");
    $fatal(1);
  end

endmodule : tb_shift_rr
