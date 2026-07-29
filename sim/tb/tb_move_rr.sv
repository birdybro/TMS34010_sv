// -----------------------------------------------------------------------------
// tb_move_rr.sv
//
// Tests MOVE Rs, Rd (register-to-register move). Per SPVU001A page 12-126
// and the summary table (verified against both the 1986 first edition and
// the 1988 User's Guide), the encoding is `0100 11MS SSSR DDDD` (base
// 0x4C00):
//   - M = bit[9]: 0 = both registers in one file, 1 = cross-file.
//   - R = bit[4]: file for both registers (M=0), or the SOURCE file (M=1;
//                 destination is the other file).
//   - Rs = bits[8:5], Rd = bits[3:0].
//
// This is NOT a field move (no F bit): all 32 bits are copied, field size
// has no effect. It is the only MOVE that can cross register files.
//
// Operation: Rs -> Rd, source unchanged, implicit compare-to-0 of the
// moved data. Status bits: N = data[31], Z = (data==0), V = 0, C
// Unaffected.
//
// NOTE: this corrects a prior bug where reg-to-reg MOVE was decoded at
// 0x9000 (`1001 00FS`), which is actually MOVE Rs,*Rd+ (a memory store).
// See assumptions.md A0020 and Task 0058.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_rr;
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
    .clk             (clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata), .mem_srt(),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(64)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction

  // MOVE Rs,Rd: 0x4C00 | (M<<9) | (Rs<<5) | (R<<4) | Rd.
  //   src_file = R; M = (src_file != dst_file).
  function automatic instr_word_t move_rr_enc(input reg_file_t src_file,
                                              input reg_idx_t  rs,
                                              input reg_file_t dst_file,
                                              input reg_idx_t  rd);
    logic m;
    m = (src_file != dst_file);
    move_rr_enc = 16'h4C00
                | (instr_word_t'(m)        << 9)
                | (instr_word_t'(rs)       << 5)
                | (instr_word_t'(src_file) << 4)
                | (instr_word_t'(rd));
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
    failures = 0;

    // Encoding sanity (against TI's own object-code examples):
    //   MOVE A1, A2 (same file A, M=0) = 0100_11_0_0001_0_0010 = 0x4C22
    //   MOVE B5, B7 (same file B, M=0) = 0100_11_0_0101_1_0111 = 0x4CB7
    //   MOVE A0, B1 (cross A->B, M=1)  = 0100_11_1_0000_0_0001 = 0x4E01  (Fig 12-3)
    //   MOVE B3, A4 (cross B->A, M=1)  = 0100_11_1_0011_1_0100 = 0x4E74
    if (move_rr_enc(REG_FILE_A, 4'd1, REG_FILE_A, 4'd2) !== 16'h4C22) begin
      $display("TEST_RESULT: FAIL: enc MOVE A1,A2 = %04h, expected 4C22",
               move_rr_enc(REG_FILE_A, 4'd1, REG_FILE_A, 4'd2)); failures++;
    end
    if (move_rr_enc(REG_FILE_B, 4'd5, REG_FILE_B, 4'd7) !== 16'h4CB7) begin
      $display("TEST_RESULT: FAIL: enc MOVE B5,B7 = %04h, expected 4CB7",
               move_rr_enc(REG_FILE_B, 4'd5, REG_FILE_B, 4'd7)); failures++;
    end
    if (move_rr_enc(REG_FILE_A, 4'd0, REG_FILE_B, 4'd1) !== 16'h4E01) begin
      $display("TEST_RESULT: FAIL: enc MOVE A0,B1 = %04h, expected 4E01",
               move_rr_enc(REG_FILE_A, 4'd0, REG_FILE_B, 4'd1)); failures++;
    end
    if (move_rr_enc(REG_FILE_B, 4'd3, REG_FILE_A, 4'd4) !== 16'h4E74) begin
      $display("TEST_RESULT: FAIL: enc MOVE B3,A4 = %04h, expected 4E74",
               move_rr_enc(REG_FILE_B, 4'd3, REG_FILE_A, 4'd4)); failures++;
    end

    // Program:
    //   same-file:  MOVI val,A1 ; MOVE A1,A2       -> A2 = val
    //               MOVI 0,A3   ; MOVE A3,A4       -> A4 = 0 (Z=1)
    //               MOVI MIN,A5 ; MOVE A5,A6       -> A6 = MIN_INT (N=1)
    //               MOVI val,B1 ; MOVE B1,B2       -> B2 = val (B file)
    //   cross-file: MOVI val,A7 ; MOVE A7,B8       -> B8 = val (A->B)
    //               MOVI val,B9 ; MOVE B9,A10      -> A10 = val (B->A)
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'hCAFE_BABE);
    u_mem.mem[p] = move_rr_enc(REG_FILE_A, 4'd1, REG_FILE_A, 4'd2); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'd0);
    u_mem.mem[p] = move_rr_enc(REG_FILE_A, 4'd3, REG_FILE_A, 4'd4); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'h8000_0000);
    u_mem.mem[p] = move_rr_enc(REG_FILE_A, 4'd5, REG_FILE_A, 4'd6); p = p + 1;

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'hDEAD_BEEF);
    u_mem.mem[p] = move_rr_enc(REG_FILE_B, 4'd1, REG_FILE_B, 4'd2); p = p + 1;

    // Cross-file A7 -> B8.
    p = place_movi_il(p, REG_FILE_A, 4'd7, 32'h1234_5678);
    u_mem.mem[p] = move_rr_enc(REG_FILE_A, 4'd7, REG_FILE_B, 4'd8); p = p + 1;

    // Cross-file B9 -> A10.
    p = place_movi_il(p, REG_FILE_B, 4'd9, 32'h0F0F_F0F0);
    u_mem.mem[p] = move_rr_enc(REG_FILE_B, 4'd9, REG_FILE_A, 4'd10); p = p + 1;

    u_mem.mem[p] = 16'hC0FF; p = p + 1;     // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (400) @(posedge clk);
    #1;

    check_reg("A1 unchanged",        u_core.u_regfile.a_regs[1],  32'hCAFE_BABE);
    check_reg("A2 = A1",             u_core.u_regfile.a_regs[2],  32'hCAFE_BABE);
    check_reg("A4 = A3 (zero)",      u_core.u_regfile.a_regs[4],  32'd0);
    check_reg("A6 = A5 (MIN_INT)",   u_core.u_regfile.a_regs[6],  32'h8000_0000);
    check_reg("B2 = B1 (B-file)",    u_core.u_regfile.b_regs[2],  32'hDEAD_BEEF);
    check_reg("B8 = A7 (A->B cross)", u_core.u_regfile.b_regs[8],  32'h1234_5678);
    check_reg("A10 = B9 (B->A cross)",u_core.u_regfile.a_regs[10], 32'h0F0F_F0F0);
    // Source registers in cross-file moves must be unchanged.
    check_reg("A7 unchanged (src)",  u_core.u_regfile.a_regs[7],  32'h1234_5678);
    check_reg("B9 unchanged (src)",  u_core.u_regfile.b_regs[9],  32'h0F0F_F0F0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE Rs,Rd: same-file + A<->B cross-file at corrected opcode 0x4C00)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_move_rr hard timeout");
    $fatal(1);
  end

endmodule : tb_move_rr
