// -----------------------------------------------------------------------------
// tb_pixt.sv
//
// PIXT (pixel transfer), linear forms — Task 0083. The first graphics
// instruction. PIXT is a field move whose field size is the PSIZE I/O
// register value (1/2/4/8/16). Per SPVU001A 12-? :
//   PIXT Rs,*Rd  (0xF800): store the low PSIZE bits of Rs to mem[*Rd]. Flags
//                          Unaffected.
//   PIXT *Rs,Rd  (0xFA00): load the PSIZE-bit pixel at mem[*Rs], right-
//                          justified and ZERO-extended (unlike MOVB's sign-
//                          extend). V = (pixel != 0); N/C/Z Undefined.
//   PIXT *Rs,*Rd (0xFC00): pixel copy mem[*Rd] <- mem[*Rs]. Flags Unaffected.
// Replace mode only (PMASK / transparency / PPOP at their reset defaults).
//
// PSIZE is set with a MOVE to the on-chip I/O register (0xC0000150), exercising
// the I/O path landed in Task 0082.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixt;
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
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic fe, input logic f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
  endfunction
  function automatic instr_word_t pixt_store_enc(input reg_idx_t rs, input reg_idx_t rd);
    pixt_store_enc = 16'hF800 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t pixt_load_enc(input reg_idx_t rs, input reg_idx_t rd);
    pixt_load_enc = 16'hFA00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t pixt_m2m_enc(input reg_idx_t rs, input reg_idx_t rd);
    pixt_m2m_enc = 16'hFC00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction
  // MOVE Rs,@DAddr store (used to set PSIZE): 0x0580 | Rs, addr LSW, MSW.
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_word(input string label, input int unsigned widx,
                            input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask
  task automatic check_v(input string label, input logic [DATA_WIDTH-1:0] st,
                         input logic v);
    if (st[ST_V_BIT] !== v) begin
      $display("TEST_RESULT: FAIL: %s: exp V=%0b got %0b", label, v, st[ST_V_BIT]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE = IO_BASE_ADDR + (IO_IDX_PSIZE << 4); // C0000150

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000; // clear data region

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-PSIZE
    // ---- PSIZE = 8 -----------------------------------------------------
    p = place_movi_il(p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE <- 8
    // 1) Store pixel 0xC3 at 0x800; 2) load it back zero-extended; V=1.
    p = place_movi_il(p, 4'd1, 32'h0000_00C3);
    p = place_movi_il(p, 4'd2, 32'h0000_0800);
    p = place_word(p, pixt_store_enc(4'd1, 4'd2));       // mem[0x800] <- 0xC3 (8b)
    p = place_word(p, pixt_load_enc (4'd2, 4'd3));       // A3 <- 0x000000C3 (zext)
    p = place_word(p, getst_enc(4'd4));                  // V=1
    // 3) M2M pixel copy 0x800 -> 0x900.
    p = place_movi_il(p, 4'd5, 32'h0000_0900);
    p = place_word(p, pixt_m2m_enc(4'd2, 4'd5));         // mem[0x900] <- mem[0x800]
    // 4) Zero pixel: store 0 at 0xA00, load -> 0, V=0.
    p = place_movi_il(p, 4'd6, 32'h0000_0000);
    p = place_movi_il(p, 4'd7, 32'h0000_0A00);
    p = place_word(p, pixt_store_enc(4'd6, 4'd7));
    p = place_word(p, pixt_load_enc (4'd7, 4'd8));       // A8 <- 0
    p = place_word(p, getst_enc(4'd9));                  // V=0
    // ---- PSIZE = 4 -----------------------------------------------------
    p = place_movi_il(p, 4'd0, 32'h0000_0004);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE <- 4
    // 5) Store 4-bit pixel 0xA at 0xB00, load -> 0x0000000A.
    p = place_movi_il(p, 4'd10, 32'h0000_000A);
    p = place_movi_il(p, 4'd11, 32'h0000_0B00);
    p = place_word(p, pixt_store_enc(4'd10, 4'd11));     // mem[0xB00] <- 0xA (4b)
    p = place_word(p, pixt_load_enc (4'd11, 4'd12));     // A12 <- 0x0000000A

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // 1/2) PSIZE=8 store + zero-extend load.
    check_word("1: mem[128] = 0x00C3",  128, 16'h00C3);
    check_reg ("2: A3 = 0x000000C3 (zext)", u_core.u_regfile.a_regs[3], 32'h0000_00C3);
    check_v   ("2: load V=1 (pixel!=0)", u_core.u_regfile.a_regs[4], 1'b1);
    // 3) M2M copy.
    check_word("3: mem[144] = 0x00C3",  144, 16'h00C3);
    // 4) Zero pixel.
    check_reg ("4: A8 = 0",             u_core.u_regfile.a_regs[8], 32'h0000_0000);
    check_v   ("4: load V=0 (pixel==0)", u_core.u_regfile.a_regs[9], 1'b0);
    // 5) PSIZE=4 pixel.
    check_word("5: mem[176] = 0x000A",  176, 16'h000A);
    check_reg ("5: A12 = 0x0000000A",   u_core.u_regfile.a_regs[12], 32'h0000_000A);
    // PSIZE register holds 4 now.
    if (u_core.u_io_regs.io_reg[IO_IDX_PSIZE] !== 16'h0004) begin
      $display("TEST_RESULT: FAIL: PSIZE reg = %04h, expected 0004",
               u_core.u_io_regs.io_reg[IO_IDX_PSIZE]);
      failures++;
    end

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PIXT linear: store/load/M2M at FS=PSIZE, zero-extend, V=pixel!=0)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_pixt hard timeout");
    $fatal(1);
  end

endmodule : tb_pixt
