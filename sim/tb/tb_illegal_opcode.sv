// -----------------------------------------------------------------------------
// tb_illegal_opcode.sv
//
// Architectural illegal-opcode interrupt integration (Task 0122).
// 1988 TMS34010 User's Guide §8.7 specifies that reserved encodings cause an
// unmaskable interrupt equivalent to TRAP 30, using vector address
// 0xFFFF_FC20. The already-fetched opcode advances PC by one word before
// decode, so entry must push that post-opcode PC and the old ST, decrement SP
// by 64 bits, install ST_RESET_VALUE, fetch vector 30, and run its handler.
//
// This test uses reserved opcode 0x0200 from the guide's Table 8-6 and checks
// the complete bus-visible sequence plus the sticky diagnostic output.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_illegal_opcode;
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
  instr_word_t                   probe_instr;
  decoded_instr_t                probe_decoded;

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

  // Direct decoder probe checks every Table 8-6 range boundary in addition
  // to the end-to-end 0x0200 trap below.
  tms34010_decode u_decode_probe (
    .instr  (probe_instr),
    .decoded(probe_decoded)
  );

  // Vector 30 aliases to word indices 962/963 in this bounded model:
  // (0xFFFF_FC20 >> 4) & 0x3FF = 0x3C2.
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t idx);
    return 16'h09E0 | instr_word_t'(idx);
  endfunction

  function automatic int unsigned place_movi_il(
      input int unsigned p,
      input reg_idx_t idx,
      input logic [DATA_WIDTH-1:0] imm
  );
    u_mem.mem[p]     = movi_il_enc(idx);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_word(
      input int unsigned p,
      input instr_word_t word
  );
    u_mem.mem[p] = word;
    return p + 1;
  endfunction

  localparam logic [DATA_WIDTH-1:0] SP_INIT       = 32'h0000_0800;
  localparam logic [DATA_WIDTH-1:0] SERVICE_PC    = 32'h0000_0640;
  localparam logic [DATA_WIDTH-1:0] PRE_ILLEGAL_ST = 32'hCAFE_BABE;
  localparam instr_word_t           ILLEGAL_WORD  = 16'h0200;
  localparam int unsigned           VEC_WORD_LO   = 962;
  localparam int unsigned           VEC_WORD_HI   = 963;

  int unsigned failures;
  int unsigned push_pc_acks;
  int unsigned push_st_acks;
  int unsigned vector_acks;
  logic [DATA_WIDTH-1:0] expected_resume_pc;
  bit saw_decode;
  bit saw_illegal;

  task automatic fail(input string message);
    $display("TEST_RESULT: FAIL: %s", message);
    failures++;
  endtask

  task automatic check_word(
      input string label,
      input logic [DATA_WIDTH-1:0] actual,
      input logic [DATA_WIDTH-1:0] expected
  );
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  task automatic check_illegal_class(
      input instr_word_t word,
      input logic expected
  );
    probe_instr = word;
    #1;
    if (probe_decoded.illegal_trap !== expected) begin
      $display("TEST_RESULT: FAIL: illegal range classification word=%04h expected=%0b actual=%0b",
               word, expected, probe_decoded.illegal_trap);
      failures++;
    end
  endtask

  always @(posedge clk) begin
    if (!rst) begin
      if (state_w == CORE_DECODE && instr_w == ILLEGAL_WORD) begin
        saw_decode = 1'b1;
      end
      if (state_w == CORE_EXECUTE && instr_w == ILLEGAL_WORD)
        fail("illegal opcode reached CORE_EXECUTE");
      if (illegal_w) saw_illegal = 1'b1;
      if (saw_illegal && !illegal_w) fail("illegal_opcode_o was not sticky");

      if (mem_req && mem_ack) begin
        unique case (state_w)
          CORE_INT_PUSH_PC: begin
            push_pc_acks++;
            if (!mem_we) fail("illegal entry PC push was not a write");
            if (mem_addr !== SP_INIT - WORD_BIT_SIZE)
              fail("illegal entry PC push used the wrong address");
            if (mem_size !== MEM_SIZE_32)
              fail("illegal entry PC push was not 32 bits");
            if (mem_wdata !== expected_resume_pc)
              fail("illegal entry pushed the wrong resume PC");
          end
          CORE_INT_PUSH_ST: begin
            push_st_acks++;
            if (!mem_we) fail("illegal entry ST push was not a write");
            if (mem_addr !== SP_INIT - WORD_BIT_SIZE_2)
              fail("illegal entry ST push used the wrong address");
            if (mem_size !== MEM_SIZE_32)
              fail("illegal entry ST push was not 32 bits");
            if (mem_wdata !== PRE_ILLEGAL_ST)
              fail("illegal entry pushed the wrong status value");
          end
          CORE_INT_VECTOR: begin
            vector_acks++;
            if (mem_we) fail("illegal entry vector fetch was a write");
            if (mem_addr !== INT_VEC_ILLOP)
              fail("illegal entry did not fetch vector 30");
            if (mem_size !== MEM_SIZE_32)
              fail("illegal entry vector fetch was not 32 bits");
          end
          default: ;
        endcase
      end
    end
  end

  initial begin : main
    int unsigned p;
    int unsigned illegal_word_idx;
    failures          = 0;
    push_pc_acks       = 0;
    push_st_acks       = 0;
    vector_acks        = 0;
    expected_resume_pc = '0;
    saw_decode         = 1'b0;
    saw_illegal        = 1'b0;
    probe_instr        = '0;

    check_illegal_class(16'h0200, 1'b1);
    check_illegal_class(16'h02FF, 1'b1);
    check_illegal_class(16'h0400, 1'b1);
    check_illegal_class(16'h04FF, 1'b1);
    check_illegal_class(16'h0800, 1'b1);
    check_illegal_class(16'h08FF, 1'b1);
    check_illegal_class(16'h0A00, 1'b1);
    check_illegal_class(16'h0AFF, 1'b1);
    check_illegal_class(16'h0C00, 1'b1);
    check_illegal_class(16'h0CFF, 1'b1);
    check_illegal_class(16'h0E00, 1'b1);
    check_illegal_class(16'h0EFF, 1'b1);
    check_illegal_class(16'h3400, 1'b1);
    check_illegal_class(16'h37FF, 1'b1);
    check_illegal_class(16'h7000, 1'b1);
    check_illegal_class(16'h7FFF, 1'b1);
    check_illegal_class(16'h9E00, 1'b1);
    check_illegal_class(16'h9FFF, 1'b1);
    check_illegal_class(16'hBE00, 1'b1);
    check_illegal_class(16'hBFFF, 1'b1);
    check_illegal_class(16'hD800, 1'b1);
    check_illegal_class(16'hDEFF, 1'b1);
    check_illegal_class(16'hFE00, 1'b1);
    check_illegal_class(16'hFFFF, 1'b1);
    check_illegal_class(16'h0000, 1'b0);
    check_illegal_class(16'h0300, 1'b0);
    check_illegal_class(16'h33FF, 1'b0);
    check_illegal_class(16'h3800, 1'b0);
    check_illegal_class(16'h6FFF, 1'b0);
    check_illegal_class(16'h8000, 1'b0);
    check_illegal_class(16'h9DFF, 1'b0);
    check_illegal_class(16'hA000, 1'b0);
    check_illegal_class(16'hBDFF, 1'b0);
    check_illegal_class(16'hC000, 1'b0);
    check_illegal_class(16'hD7FF, 1'b0);
    check_illegal_class(16'hDF00, 1'b0);
    check_illegal_class(16'hFDFF, 1'b0);

    for (int unsigned i = 0; i < 1024; i++) begin
      u_mem.mem[i] = 16'h0300; // NOP
    end

    // Trap-30 handler: leave an execution marker and halt.
    p = 100;
    p = place_movi_il(p, 4'd5, 32'h0000_BEEF);
    u_mem.mem[p] = 16'hC0FF;
    u_mem.mem[VEC_WORD_LO] = SERVICE_PC[15:0];
    u_mem.mem[VEC_WORD_HI] = SERVICE_PC[31:16];

    // Main: initialize SP and a distinguishable ST, then execute a reserved
    // word. The instruction after it must never execute.
    p = 0;
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F); // MOVE A2,A15
    p = place_movi_il(p, 4'd1, PRE_ILLEGAL_ST);
    p = place_word(p, 16'h01A1); // PUTST A1
    illegal_word_idx = p;
    p = place_word(p, ILLEGAL_WORD);
    expected_resume_pc = DATA_WIDTH'(p) << 4;
    p = place_movi_il(p, 4'd6, 32'h0000_DEAD);
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    #1;
    rst = 1'b0;

    repeat (3000) @(posedge clk);
    #1;

    if (!saw_decode) fail("reserved opcode never reached CORE_DECODE");
    if (!saw_illegal) fail("illegal_opcode_o never asserted");
    if (push_pc_acks != 1) fail("illegal entry did not acknowledge exactly one PC push");
    if (push_st_acks != 1) fail("illegal entry did not acknowledge exactly one ST push");
    if (vector_acks != 1) fail("illegal entry did not acknowledge exactly one vector read");

    check_word("handler marker A5",
               u_core.u_regfile.a_regs[5], 32'h0000_BEEF);
    check_word("post-illegal marker A6 stayed clear",
               u_core.u_regfile.a_regs[6], 32'h0000_0000);
    check_word("SP decremented by two words",
               u_core.u_regfile.sp_q, SP_INIT - WORD_BIT_SIZE_2);
    check_word("post-entry ST",
               u_core.u_status_reg.st_q, ST_RESET_VALUE);
    check_word("stacked resume PC",
               {u_mem.mem[127], u_mem.mem[126]}, expected_resume_pc);
    check_word("stacked pre-illegal ST",
               {u_mem.mem[125], u_mem.mem[124]}, PRE_ILLEGAL_ST);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (illegal word %04h at word %0d trapped through vector 30)",
               ILLEGAL_WORD, illegal_word_idx);
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_illegal_opcode hard timeout");
    $fatal(1);
  end

endmodule : tb_illegal_opcode
