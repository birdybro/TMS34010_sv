// -----------------------------------------------------------------------------
// tb_nmi.sv
//
// Nonmaskable interrupt, context-saving mode (NMIM=0). Per 1988 UG §8: the host
// sets HSTCTLH.NMI (bit 8); the device — regardless of ST.IE — pushes PC+ST,
// auto-clears the NMI bit, and vectors through trap 8 (0xFFFFFEE0). This test
// leaves IE=0 to prove non-maskability, then returns via RETI.
//
//   main:  set SP, write HSTCTLH = NMI (NMIM=0); IE stays 0
//          <resume target: MOVI A6,0x1234>   ; skipped on entry, run after RETI
//          halt
//   ISR :  MOVI A5,0xBEEF, RETI
//
// Checks: A5=0xBEEF (NMI taken despite IE=0), A6=0x1234 (resumed via RETI),
// SP=SP_INIT (push undone), HSTCTLH.NMI auto-cleared (no re-trigger).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_nmi;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req, mem_we, mem_ack;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata, mem_rdata;
  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_srt(), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );
  sim_memory_model #(.DEPTH_WORDS(1024)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p]=w; place_word=p+1;
  endfunction
  function automatic int unsigned place_store_abs(input int unsigned p, input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]=16'h0580|instr_word_t'(rs); u_mem.mem[p+1]=addr[15:0]; u_mem.mem[p+2]=addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label, input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask

  localparam logic [DATA_WIDTH-1:0] SP_INIT    = 32'h0000_0800;
  localparam logic [DATA_WIDTH-1:0] SERVICE_PC = 32'h0000_0640; // word 100
  localparam logic [31:0] A_HSTCTLH = IO_BASE_ADDR + (IO_IDX_HSTCTLH << 4); // C0000100
  localparam logic [15:0] NMI_REQ_NMIM0 = 16'(1 << HSTCTL_NMI_BIT);        // 0x0100
  localparam int unsigned VEC_LO = 1006, VEC_HI = 1007; // 0xFFFFFEE0 aliases here

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 1024; i++) u_mem.mem[i] = 16'h0300;

    // ISR (word 100): A5 <- 0xBEEF, RETI.
    p = 100;
    p = place_movi_il(p, 4'd5, 32'h0000_BEEF);
    p = place_word(p, 16'h0940);                   // RETI

    u_mem.mem[VEC_LO] = SERVICE_PC[15:0];
    u_mem.mem[VEC_HI] = SERVICE_PC[31:16];

    // Main (word 0): set SP, request NMI (NMIM=0). IE left 0 (non-maskable).
    p = 0;
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);                   // MOVE A2,A15
    p = place_movi_il(p, 4'd0, {16'h0, NMI_REQ_NMIM0});
    p = place_store_abs(p, 4'd0, A_HSTCTLH);       // HSTCTLH <- NMI
    // Resume target (skipped on entry, run after RETI):
    p = place_movi_il(p, 4'd6, 32'h0000_1234);
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_reg("NMI: handler ran despite IE=0 (A5=0xBEEF)",
              u_core.u_regfile.a_regs[5], 32'h0000_BEEF);
    check_reg("NMI: resumed via RETI (A6=0x1234)",
              u_core.u_regfile.a_regs[6], 32'h0000_1234);
    check_reg("NMI: SP restored (push undone by RETI)",
              u_core.u_regfile.sp_q, SP_INIT);
    if (u_core.u_io_regs.io_reg[IO_IDX_HSTCTLH][HSTCTL_NMI_BIT] !== 1'b0) begin
      $display("TEST_RESULT: FAIL: HSTCTLH.NMI not auto-cleared");
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (NMI NMIM=0: taken despite IE=0, PC/ST pushed, vector taken, auto-cleared, RETI resumes)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_nmi hard timeout");
    $fatal(1);
  end
endmodule : tb_nmi
