// -----------------------------------------------------------------------------
// tb_reti.sv
//
// RETI — Return from Interrupt. Per SPVU001A page 12-230 + summary
// table line 27037. Single fixed encoding 0x0940. Semantics:
//
//   ST <- mem[SP];     SP <- SP + 32   (step 0: restore ST)
//   PC <- mem[SP];     SP <- SP + 32   (step 1: restore PC)
//
// This is the first multi-transaction memory instruction in the
// project. The core's new `mem_op_step` counter sequences the two
// 32-bit reads; `popped_st_q` and `popped_pc_q` latch the values
// for use in WRITEBACK.
//
// Test plan — synthesize the interrupted-routine stack frame manually
// (no TRAP yet, since that's the next task):
//
//   1. Initialize SP to mid-memory (0x0000_0800 = bit-address of
//      word 128).
//   2. Pre-place stack frame in memory:
//        mem[word 128..129] (= SP) = saved ST (= 0xCAFE_BABE).
//        mem[word 130..131] (= SP+32 bits) = saved PC (= bit-addr of
//          word 200 = 0x0000_0C80).
//   3. Pre-place a halt sentinel (0xC0FF) at word 200. Importantly,
//      this routine MUST NOT modify N/Z/C/V — a normal arithmetic
//      instruction here would update flags and overwrite the popped
//      ST's top nibble before we could observe it.
//   4. RETI.
//   5. Verify:
//        ST  = 0xCAFE_BABE                 (popped from step 0)
//        PC  ≈ word 200 region              (popped from step 1)
//        SP  = 0x0000_0840                  (= 0x0800 + 64)
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_reti;
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

  localparam logic [DATA_WIDTH-1:0] SP_INIT    = 32'h0000_0800;  // bit-addr of word 128
  localparam logic [DATA_WIDTH-1:0] SAVED_ST   = 32'hCAFE_BABE;
  localparam logic [DATA_WIDTH-1:0] SAVED_PC   = 32'h0000_0C80;  // bit-addr of word 200

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // NOP-fill.
    for (i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Pre-build the interrupted-routine stack frame ------------------
    // The lower-address slot (SP) holds the saved ST; the upper slot
    // (SP+32) holds the saved PC.  Each is 32 bits, split across two
    // 16-bit words in our memory model.
    //   words 128, 129 = SAVED_ST (low, high)
    //   words 130, 131 = SAVED_PC (low, high)
    u_mem.mem[128] = SAVED_ST[15:0];
    u_mem.mem[129] = SAVED_ST[31:16];
    u_mem.mem[130] = SAVED_PC[15:0];
    u_mem.mem[131] = SAVED_PC[31:16];

    // ---- Place a HALT sentinel at word 200 ------------------------------
    // The interrupted routine in this test is just a single halt: we
    // can't run a real instruction here, because any arithmetic /
    // move would update N/Z (and possibly C/V) and clobber the very
    // ST flag bits we're about to check.
    u_mem.mem[200] = 16'hC0FF;

    p = 0;

    // ---- Prelude: MOVE A0=SP_INIT into A15 (SP) ------------------------
    p = place_movi_il(p, 4'd0, SP_INIT);
    u_mem.mem[p] = 16'h4C0F; p = p + 1;        // MOVE A0, A15

    // ---- RETI ----------------------------------------------------------
    u_mem.mem[p] = 16'h0940; p = p + 1;

    // ---- (No instructions after RETI in this region; control transfers
    //      to word 200 via the popped PC.)

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (2000) @(posedge clk);
    #1;

    // ---- Checks --------------------------------------------------------
    // ST should now hold the popped value (SAVED_ST = 0xCAFE_BABE).
    check_reg("RETI: ST <- popped ST (from step 0)",
              u_core.u_status_reg.st_q, SAVED_ST);

    // PC must lie in the popped region (= bit-addr of word 200 = 0x0C80,
    // possibly +16 after fetching the halt sentinel). Anything < 0x0C80
    // would mean the second pop never updated PC.
    if (pc_w < SAVED_PC) begin
      $display("TEST_RESULT: FAIL: RETI: PC not at popped target: expected>=%08h actual=%08h",
               SAVED_PC, pc_w);
      failures++;
    end

    // SP incremented by 64 (= 32 + 32 for the two pops).
    check_reg("RETI: SP <- SP_INIT + 64",
              u_core.u_regfile.sp_q, SP_INIT + 32'd64);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (RETI: ST restored, PC restored, SP += 64)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_reti hard timeout");
    $fatal(1);
  end

endmodule : tb_reti
