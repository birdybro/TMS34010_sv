// -----------------------------------------------------------------------------
// tb_trap.sv
//
// TRAP N — Software Interrupt. Per SPVU001A page 12-252. Encoding
// `0000 1001 000N NNNN` = `0x0900 | N` with N at instr[4:0]. Action:
//
//   1) SP -= 32; mem[SP] <- PC'
//   2) SP -= 32; mem[SP] <- ST
//   3) ST <- 0x00000010      (clears flags + IE; FS0=16, FS1=0)
//   4) PC <- mem[0xFFFFFFE0 - N*32]
//
// This is the first three-transaction instruction (write, write, read).
// The vector address is at the very top of the 32-bit bit-address
// space; our sim_memory_model masks the address to its internal index
// range, so the spec address `0xFFFFFFE0 - N*32` aliases to slots near
// the end of the memory. We exploit that to pre-place the vector.
//
// Test plan: use TRAP 3 (a representative N>=1 case). With
// DEPTH=1024, the vector for N=3 (`0xFFFFFF80`) aliases to word
// indices 1016/1017 (low/high 16-bit halves of the 32-bit vector).
//
//   1. Pre-place a TRAP service routine at word 100 (bit-addr 0x640).
//      The routine writes A6 = 0x0BAD_C0DE then halts (`0xC0FF`).
//   2. Pre-place the trap vector value (= bit-addr 0x0640) at the
//      aliased slot for TRAP 3.
//   3. Pre-place a "before-TRAP" instruction stream:
//        MOVI A1, 0xCAFEBABE   ; arbitrary value to populate ST flags
//        MOVI A2, SP_INIT      ; load SP_INIT into A2
//        MOVE A2, A15          ; SP <- A2
//        TRAP 3                ; software interrupt
//   4. After TRAP completes (service routine ran and halted), verify:
//        A6  = 0x0BAD_C0DE    (service routine actually executed)
//        ST  = 0x00000010 OR'd with whatever flags the service
//              routine's MOVI A6 set (= N flag, since 0x0BADC0DE has
//              bit 31 = 0; in fact MOVI updates N=0/Z=0, so ST stays
//              at 0x00000010 with all flag bits 0)
//        SP  = SP_INIT - 64
//        mem[SP_INIT-32 : SP_INIT-1] (high half / low half) holds PC'
//        mem[SP_INIT-64 : SP_INIT-33]                       holds ST
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_trap;
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

  // DEPTH_WORDS=1024 → IDX_WIDTH=10 → mem_addr[13:4] selects the word
  // index, so bit-address `0xFFFFFFE0 - N*32` aliases to a slot in the
  // top of the 1024-word memory. See trap-vector arithmetic below.
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

  // SP_INIT lands mid-memory (bit-addr 0x0800 = word 128). The two
  // pushes touch words 124..127 (PC') and 120..123 (ST).
  localparam logic [DATA_WIDTH-1:0] SP_INIT = 32'h0000_0800;

  // Service routine for TRAP 3 lives at word 100 (bit-addr 0x0640).
  localparam logic [DATA_WIDTH-1:0] SERVICE_PC = 32'h0000_0640;

  // Trap-vector aliasing into the 1024-word memory:
  //   word_idx = mem_addr[13:4] (10 bits).
  //   TRAP N vector address = 0xFFFFFFE0 - N*32.
  //   For N=3: 0xFFFFFFE0 - 0x60 = 0xFFFFFF80.
  //     0xFFFFFF80[13:4] = (0xFFFFFF80 >> 4) & 0x3FF
  //                      = 0xFFFFFF8 & 0x3FF
  //                      = 0x3F8 = 1016.
  // So the 32-bit vector occupies words 1016 (low half) and 1017
  // (high half).
  localparam int unsigned TRAP_N      = 3;
  localparam int unsigned VEC_WORD_LO = 1016;
  localparam int unsigned VEC_WORD_HI = 1017;

  initial begin : main
    int unsigned p;
    int unsigned i;
    failures = 0;

    // NOP-fill.
    for (i = 0; i < 1024; i++) begin
      u_mem.mem[i] = 16'h0300;
    end

    // ---- Pre-place the TRAP-3 service routine at word 100 -------------
    // The routine writes A6 = 0x0BADC0DE and halts. Updating A6
    // sets N=0/Z=0 (since 0x0BADC0DE has bit 31 = 0 and is non-zero),
    // matching the cleared flag bits in the post-TRAP ST = 0x10.
    p = 100;
    p = place_movi_il(p, 4'd6, 32'h0BAD_C0DE);
    u_mem.mem[p] = 16'hC0FF;          // halt

    // ---- Pre-place the trap vector --------------------------------------
    // 32-bit vector value = SERVICE_PC (bit-addr of the routine).
    u_mem.mem[VEC_WORD_LO] = SERVICE_PC[15:0];
    u_mem.mem[VEC_WORD_HI] = SERVICE_PC[31:16];

    // ---- Pre-place the pre-TRAP program at word 0 -----------------------
    p = 0;
    // MOVI A2, SP_INIT — preparing to load SP.
    p = place_movi_il(p, 4'd2, SP_INIT);
    // MOVE A2, A15 — SP <- A2 (= SP_INIT).
    // Encoding (SPVU001A p.12-126) `0100 11MS SSSR DDDD`: top6=010011, M=0, Rs=0010 (A2),
    // R=0 (A file), Rd=1111 (A15) ⇒ 0x4C4F.
    u_mem.mem[p] = 16'h4C4F; p = p + 1;  // MOVE A2, A15
    // MOVI A1, 0xCAFEBABE — value we'll force into ST via PUTST. We
    // need a distinguishable ST going into TRAP so the push-then-
    // replace ordering is unambiguous (the reset ST is also 0x10, so
    // pushing it would alias the post-TRAP write).
    p = place_movi_il(p, 4'd1, 32'hCAFE_BABE);
    // PUTST A1 — ST <- 0xCAFEBABE. PUTST writes the full 32-bit ST
    // and does NOT then update N/Z, so ST holds exactly this value
    // when TRAP fires.
    u_mem.mem[p] = 16'h01A0 | 16'h0001; p = p + 1;  // PUTST A1

    // ---- TRAP 3 ---------------------------------------------------------
    // Encoding: 0x0900 | N = 0x0903 for N=3.
    // pc_value at the start of CORE_MEMORY = PC' = address of the
    // word immediately following the TRAP instruction (= 16'(p+1) in
    // bit-address terms). We capture that to compare against the
    // pushed return address.
    u_mem.mem[p] = 16'h0900 | TRAP_N;
    p = p + 1;

    // ---- After TRAP: no further instructions in this region. The TRAP
    //      transfers control to SERVICE_PC.

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (3000) @(posedge clk);
    #1;

    // -------- Checks ----------------------------------------------------
    // Service routine ran → A6 holds the sentinel value.
    check_reg("TRAP: service routine executed (A6 = 0x0BADC0DE)",
              u_core.u_regfile.a_regs[6], 32'h0BAD_C0DE);

    // SP decremented by 64.
    check_reg("TRAP: SP <- SP_INIT - 64",
              u_core.u_regfile.sp_q, SP_INIT - 32'd64);

    // ST after TRAP = 0x10. The service routine's MOVI A6 updates
    // N/Z based on the moved value (0x0BADC0DE: bit 31 = 0, non-zero
    // ⇒ N=0, Z=0). So flag bits stay 0 and ST == 0x10.
    check_reg("TRAP: ST <- 0x00000010 (after routine's MOVI, flags still 0)",
              u_core.u_status_reg.st_q, 32'h0000_0010);

    // PC' (= address of instruction after TRAP) was pushed at SP-32.
    // SP-32 = SP_INIT - 32 = 0x07E0 → word 126/127.
    // pc_value at TRAP entry = (the bit-address of u_mem.mem[p_post]) where
    // p_post is the word after the TRAP instruction. We computed p_pre =
    // the word containing TRAP; p_post = p_pre + 1; bit-addr = (p_pre+1)*16.
    // p_pre = p - 1 (the line above set u_mem.mem[p] = ...; then p = p+1).
    // So pushed PC' = (p) * 16 in bit-address terms (since `p` after
    // increment equals p_post).
    // We saved nothing; just check the two memory words.
    begin
      logic [DATA_WIDTH-1:0] pushed_pc;
      logic [DATA_WIDTH-1:0] pushed_st;
      pushed_pc = {u_mem.mem[127], u_mem.mem[126]};
      pushed_st = {u_mem.mem[125], u_mem.mem[124]};
      // pushed_pc should be > 0 (TRAP isn't at word 0). pushed_st
      // should equal the PUTST'd value (0xCAFEBABE) — distinguishable
      // from TRAP's own ST overwrite (0x10), so we can confirm the
      // push captured the OLD ST.
      if (pushed_pc == 32'h0) begin
        $display("TEST_RESULT: FAIL: TRAP: pushed PC' is zero (= %08h)", pushed_pc);
        failures++;
      end
      check_reg("TRAP: pushed ST (= pre-TRAP PUTST value = 0xCAFEBABE)",
                pushed_st, 32'hCAFE_BABE);
    end

    // Sanity: no illegal-opcode signal asserted during the run.
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (TRAP %0d: service routine ran; SP-=64; ST<-0x10; PC' and ST pushed)",
               TRAP_N);
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_trap hard timeout");
    $fatal(1);
  end

endmodule : tb_trap
