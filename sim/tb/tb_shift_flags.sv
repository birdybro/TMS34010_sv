// -----------------------------------------------------------------------------
// tb_shift_flags.sv
//
// Integration coverage for the individual shift-instruction status masks:
//   SLA       updates N/C/Z/V
//   SRA       updates N/C/Z and preserves V
//   SLL/SRL/RL update C/Z and preserve N/V
//
// Both constant and register forms are exercised. Right-shift constant
// fields and right-shift register operands contain the 5-bit two's
// complement of the architectural shift count. A fixed PUTST seed is
// restored before each operation and GETST snapshots the result.
//
// Spec: 1988 TI TMS34010 User's Guide pages 12-234/12-235 and 12-239..12-246.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_shift_flags;
  import tms34010_pkg::*;

  localparam logic [5:0] SLA_K_TOP6 = 6'b001000;
  localparam logic [5:0] SLL_K_TOP6 = 6'b001001;
  localparam logic [5:0] SRA_K_TOP6 = 6'b001010;
  localparam logic [5:0] SRL_K_TOP6 = 6'b001011;
  localparam logic [5:0] RL_K_TOP6  = 6'b001100;

  localparam logic [6:0] SLA_RR_TOP7 = 7'b0110_000;
  localparam logic [6:0] SLL_RR_TOP7 = 7'b0110_001;
  localparam logic [6:0] SRA_RR_TOP7 = 7'b0110_010;
  localparam logic [6:0] SRL_RR_TOP7 = 7'b0110_011;
  localparam logic [6:0] RL_RR_TOP7  = 7'b0110_100;

  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hF000_0010;

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
    .illegal_opcode_o(illegal_w),
    .run_emu_n_i     (1'b1),
    .emua_n_o        (), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o()
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t rd);
    movi_il_enc = 16'h09E0 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic instr_word_t getst_b_enc(input reg_idx_t rd);
    getst_b_enc = 16'h0190 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t shift_k_enc(input logic [5:0] top6,
                                              input logic [4:0] count,
                                              input reg_idx_t   rd);
    logic [4:0] opcode_k;
    begin
      opcode_k = (top6 == SRA_K_TOP6 || top6 == SRL_K_TOP6)
               ? ((~count) + 5'd1)
               : count;
      shift_k_enc = (instr_word_t'(top6) << 10)
                  | (instr_word_t'(opcode_k) << 5)
                  | instr_word_t'(rd);
    end
  endfunction

  function automatic instr_word_t shift_rr_enc(input logic [6:0] top7,
                                               input reg_idx_t   rs,
                                               input reg_idx_t   rd);
    shift_rr_enc = (instr_word_t'(top7) << 9)
                 | (instr_word_t'(rs) << 5)
                 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi(input int unsigned p,
                                             input reg_idx_t   rd,
                                             input logic [DATA_WIDTH-1:0] value);
    u_mem.mem[p]     = movi_il_enc(rd);
    u_mem.mem[p + 1] = value[15:0];
    u_mem.mem[p + 2] = value[31:16];
    place_movi = p + 3;
  endfunction

  function automatic int unsigned place_k_case(input int unsigned p,
                                               input logic [5:0] top6,
                                               input logic [4:0] count,
                                               input logic [DATA_WIDTH-1:0] data,
                                               input reg_idx_t snapshot);
    int unsigned q;
    begin
      q = place_movi(p, 4'd1, data);
      u_mem.mem[q] = putst_enc(4'd14); q++;
      u_mem.mem[q] = shift_k_enc(top6, count, 4'd1); q++;
      u_mem.mem[q] = getst_b_enc(snapshot); q++;
      place_k_case = q;
    end
  endfunction

  function automatic int unsigned place_rr_case(input int unsigned p,
                                                input logic [6:0] top7,
                                                input logic [4:0] encoded_count,
                                                input logic [DATA_WIDTH-1:0] data,
                                                input reg_idx_t snapshot);
    int unsigned q;
    begin
      q = place_movi(p, 4'd0, {{(DATA_WIDTH-5){1'b0}}, encoded_count});
      q = place_movi(q, 4'd1, data);
      u_mem.mem[q] = putst_enc(4'd14); q++;
      u_mem.mem[q] = shift_rr_enc(top7, 4'd0, 4'd1); q++;
      u_mem.mem[q] = getst_b_enc(snapshot); q++;
      place_rr_case = q;
    end
  endfunction

  int unsigned failures;

  task automatic check_word(input string label,
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
    for (i = 0; i < 256; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // Keep an all-flags-set ST seed in A14. MOVI's own status update happens
    // only once here; PUTST restores the exact seed before every shift.
    p = place_movi(0, 4'd14, ST_SEED);

    // Constant forms. B0..B4 capture full ST after each operation.
    p = place_k_case(p, SLA_K_TOP6, 5'd2, 32'h4000_0000, 4'd0);
    p = place_k_case(p, SLL_K_TOP6, 5'd1, 32'h0000_0001, 4'd1);
    p = place_k_case(p, SRA_K_TOP6, 5'd1, 32'h8000_0001, 4'd2);
    p = place_k_case(p, SRL_K_TOP6, 5'd1, 32'h0000_0002, 4'd3);
    p = place_k_case(p, RL_K_TOP6,  5'd0, 32'h0000_0000, 4'd4);

    // Register forms. Left/rotate counts are direct. Right counts are their
    // 5-bit two's complements: architectural count 1 is encoded as 31.
    p = place_rr_case(p, SLA_RR_TOP7, 5'd2,  32'h3333_3333, 4'd5);
    p = place_rr_case(p, SLL_RR_TOP7, 5'd1,  32'h8000_0000, 4'd6);
    p = place_rr_case(p, SRA_RR_TOP7, 5'd31, 32'h8000_0001, 4'd7);
    p = place_rr_case(p, SRL_RR_TOP7, 5'd31, 32'h0000_0002, 4'd8);
    p = place_rr_case(p, RL_RR_TOP7,  5'd4,  32'h1234_5678, 4'd9);
    u_mem.mem[p] = 16'hC0FF; // JRUC -1: hold after the snapshots

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (1800) @(posedge clk);
    #1;

    check_word("SLA K updates NCZV", u_core.u_regfile.b_regs[0],
               32'h7000_0010);
    check_word("SLL K preserves N/V", u_core.u_regfile.b_regs[1],
               32'h9000_0010);
    check_word("SRA K preserves V", u_core.u_regfile.b_regs[2],
               32'hD000_0010);
    check_word("SRL K preserves N/V", u_core.u_regfile.b_regs[3],
               32'h9000_0010);
    check_word("RL K=0 preserves N/V, sets C=0/Z=1",
               u_core.u_regfile.b_regs[4], 32'hB000_0010);

    check_word("SLA Rs updates NCZV", u_core.u_regfile.b_regs[5],
               32'h9000_0010);
    check_word("SLL Rs preserves N/V", u_core.u_regfile.b_regs[6],
               32'hF000_0010);
    check_word("SRA Rs preserves V", u_core.u_regfile.b_regs[7],
               32'hD000_0010);
    check_word("SRL Rs preserves N/V", u_core.u_regfile.b_regs[8],
               32'h9000_0010);
    check_word("RL Rs preserves N/V", u_core.u_regfile.b_regs[9],
               32'hD000_0010);
    check_word("final RL result", u_core.u_regfile.a_regs[1],
               32'h2345_6781);
    check_word("legal shift program", {{(DATA_WIDTH-1){1'b0}}, illegal_w},
               32'h0000_0000);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (shift encodings, overflow, and all status masks verified)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_shift_flags hard timeout");
    $fatal(1);
  end

endmodule : tb_shift_flags
