// -----------------------------------------------------------------------------
// tb_mmtm_nflag.sv
//
// MMTM N-flag semantics. Per SPVU001A page 12-111, MMTM affects ONLY the
// N status bit (C, Z, V Unaffected):
//
//   "N: Set to the sign of the result of 0 - Rp. (This value is typically
//    1 if the original contents of Rp are positive; otherwise, it is 0.
//    The only exceptions to this are when Rp=80000000h, N is set to 0,
//    and when Rp=0, N is set to 1.)"
//
// That closed form is exactly N = ~Rp[31] (the inverted sign bit of the
// ORIGINAL Rp), which the core computes in its flag_input mux. This test
// exercises the typical cases and both stated exceptions:
//
//   Rp = 0x00001000 (positive)      -> N = 1
//   Rp = 0xFFFFF000 (negative)      -> N = 0
//   Rp = 0x00000000 (zero edge)     -> N = 1   (spec exception)
//   Rp = 0x80000000 (min-neg edge)  -> N = 0   (spec exception)
//
// The N value is independent of the mask / pushes, so each case uses the
// smallest MMTM (push a single register, A0). N is captured immediately
// after each MMTM with a GETST snapshot (GETST does not modify flags), so
// the next MOVI that reloads Rp can't clobber the result before it is
// checked. Snapshots land in A2..A5; their bit[31] is the captured N.
//
// Memory writes from these MMTMs land at wrapped (Rp-32) bit addresses
// well above the tiny program region, so they don't corrupt instructions.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mmtm_nflag;
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
    .clk             (clk), .vclk_i(clk),
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
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
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

  // MOVI IL K, Rd (A-file) — 0x09E0 | N + 32-bit immediate (LO, HI).
  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = 16'h09E0 | instr_word_t'(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p,
                                             input instr_word_t w);
    u_mem.mem[p] = w;
    place_word   = p + 1;
  endfunction

  // One N-flag case: reload A1=Rp, MMTM A1,{A0}, snapshot ST into A<snap>.
  //   MMTM A1 = 0x0981, mask = 0x0001 (push A0 only).
  //   GETST A<snap> = 0x0180 | snap.
  function automatic int unsigned place_case(input int unsigned p,
                                             input logic [DATA_WIDTH-1:0] rp_val,
                                             input reg_idx_t snap);
    p = place_movi_il(p, 4'd1, rp_val);     // A1 = Rp
    p = place_word(p, 16'h0981);            // MMTM A1, mask
    p = place_word(p, 16'h0001);            //   mask = {A0}
    p = place_word(p, 16'h0180 | instr_word_t'(snap)); // GETST A<snap>
    place_case = p;
  endfunction

  int unsigned failures;
  task automatic check_n(input string label,
                         input logic [DATA_WIDTH-1:0] st_snapshot,
                         input logic                  expected_n);
    if (st_snapshot[ST_N_BIT] !== expected_n) begin
      $display("TEST_RESULT: FAIL: %s: expected N=%0b actual N=%0b (ST=%08h)",
               label, expected_n, st_snapshot[ST_N_BIT], st_snapshot);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;          // NOP-fill
    end

    // A0 holds the (don't-care) value that each MMTM pushes.
    p = 0;
    p = place_movi_il(p, 4'd0, 32'hA0A0_A0A0);

    // Four cases, snapshots into A2, A3, A4, A5.
    p = place_case(p, 32'h0000_1000, 4'd2);  // positive      -> N=1
    p = place_case(p, 32'hFFFF_F000, 4'd3);  // negative      -> N=0
    p = place_case(p, 32'h0000_0000, 4'd4);  // zero edge     -> N=1
    p = place_case(p, 32'h8000_0000, 4'd5);  // min-neg edge  -> N=0

    p = place_word(p, 16'hC0FF);             // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (3000) @(posedge clk);
    #1;

    check_n("MMTM N: Rp=0x00001000 (positive)",     u_core.u_regfile.a_regs[2], 1'b1);
    check_n("MMTM N: Rp=0xFFFFF000 (negative)",     u_core.u_regfile.a_regs[3], 1'b0);
    check_n("MMTM N: Rp=0x00000000 (zero edge)",    u_core.u_regfile.a_regs[4], 1'b1);
    check_n("MMTM N: Rp=0x80000000 (min-neg edge)", u_core.u_regfile.a_regs[5], 1'b0);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MMTM N flag = ~Rp[31]: positive/negative + both spec edge cases)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_mmtm_nflag hard timeout");
    $fatal(1);
  end

endmodule : tb_mmtm_nflag
