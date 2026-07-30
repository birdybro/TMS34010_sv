// -----------------------------------------------------------------------------
// tb_window_common_rect.sv
//
// Task 0164: CONTROL.W=1 common-rectangle results for FILL XY and every
// XY-destination PIXBLT form.
//
// Coverage:
//   * disjoint, partial, contained, enclosing, edge-touching, and empty arrays;
//   * exact DADDR/DYDX, V-only status, WVP, and unaffected SADDR results;
//   * all PBH/PBV combinations for L,XY and XY,XY;
//   * PBH/PBV isolation for FILL XY and PIXBLT B,XY;
//   * zero graphics-memory traffic and stable requests with three wait cycles;
//   * SRT enabled, proving W=1/empty results create no physical transfer.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_window_common_rect;
  import tms34010_pkg::*;

  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hE000_0010;
  localparam logic [DATA_WIDTH-1:0] SADDR_SEED = 32'h1234_5678;

  localparam logic [DATA_WIDTH-1:0] A_CONTROL =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONTROL) << 4);
  localparam logic [DATA_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [DATA_WIDTH-1:0] A_CONVSP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVSP) << 4);
  localparam logic [DATA_WIDTH-1:0] A_CONVDP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVDP) << 4);
  localparam logic [DATA_WIDTH-1:0] A_PSIZE =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PSIZE) << 4);

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req;
  logic                        mem_we;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata;
  logic                        mem_srt;
  logic [DATA_WIDTH-1:0]       mem_rdata;
  logic                        mem_ack;
  core_state_t                 state_w;
  logic [ADDR_WIDTH-1:0]       pc_w;
  instr_word_t                 instr_w;
  logic                        illegal_w;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1),
    .video_vsync_n_i(1'b1), .rst(rst), .vclk_rst_i(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_srt(mem_srt), .mem_iaq(),
    .mem_is_io(), .mem_io_we(), .mem_io_rdata(),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack), .state_o(state_w),
    .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w),
    .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1),
    .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0),
    .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00),
    .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(),
    .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(),
    .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(),
    .host_mem_is_io_o(), .host_mem_io_rdata_o(),
    .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(),
    .video_vsync_o(), .video_hblank_o(), .video_vblank_o(),
    .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(),
    .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o(),
    .screen_refresh_org_o()
  );

  sim_memory_model #(
    .DEPTH_WORDS(512),
    .WORD_WAIT_CYCLES(3)
  ) u_mem (
    .clk(clk), .rst(rst), .mem_req(mem_req), .mem_we(mem_we),
    .mem_addr(mem_addr), .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction

  function automatic instr_word_t movi_il_b_enc(input reg_idx_t i);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(i);
  endfunction

  function automatic instr_word_t setf_enc(input logic [4:0] fs);
    setf_enc = 16'b0000_0100_0000_0000
             | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000
             | instr_word_t'(fs);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_word(
      input int unsigned p,
      input instr_word_t w
  );
    u_mem.mem[p] = w;
    place_word = p + 1;
  endfunction

  function automatic int unsigned place_movi_il(
      input int unsigned p,
      input reg_idx_t i,
      input logic [DATA_WIDTH-1:0] imm
  );
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction

  function automatic int unsigned place_movi_il_b(
      input int unsigned p,
      input reg_idx_t i,
      input logic [DATA_WIDTH-1:0] imm
  );
    u_mem.mem[p]     = movi_il_b_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il_b = p + 3;
  endfunction

  function automatic int unsigned place_store_abs(
      input int unsigned p,
      input reg_idx_t rs,
      input logic [DATA_WIDTH-1:0] addr
  );
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction

  function automatic logic graphics_state(input core_state_t state);
    unique case (state)
      CORE_FILL_SETUP,
      CORE_FILL_SETUP_WIN,
      CORE_FILL_WIN_HIT,
      CORE_FILL_W1_DYDX,
      CORE_PBLT_SETUP,
      CORE_PBLT_SETUP2,
      CORE_PBLT_SETUP_WIN,
      CORE_PBLT_WIN_HIT,
      CORE_PBLT_W1_DYDX: graphics_state = 1'b1;
      default:            graphics_state = 1'b0;
    endcase
  endfunction

  int unsigned failures;
  int unsigned graphics_requests;
  logic protocol_error;
  logic saw_wait;
  logic held_req_q;
  logic held_we_q;
  logic [ADDR_WIDTH-1:0]       held_addr_q;
  logic [FIELD_SIZE_WIDTH-1:0] held_size_q;
  logic [DATA_WIDTH-1:0]       held_wdata_q;

  always @(posedge clk) begin
    if (rst) begin
      graphics_requests <= 0;
      protocol_error    <= 1'b0;
      saw_wait          <= 1'b0;
      held_req_q        <= 1'b0;
      held_we_q         <= 1'b0;
      held_addr_q       <= '0;
      held_size_q       <= '0;
      held_wdata_q      <= '0;
    end else begin
      if (graphics_state(state_w) && mem_req) begin
        graphics_requests <= graphics_requests + 1;
        if (!mem_srt) protocol_error <= 1'b1;
      end
      if (mem_req && !mem_ack) begin
        saw_wait <= 1'b1;
      end
      if (held_req_q
          && (!mem_req
              || (mem_we !== held_we_q)
              || (mem_addr !== held_addr_q)
              || (mem_size !== held_size_q)
              || (mem_wdata !== held_wdata_q))) begin
        protocol_error <= 1'b1;
      end
      if (mem_req && !mem_ack && !held_req_q) begin
        held_req_q   <= 1'b1;
        held_we_q    <= mem_we;
        held_addr_q  <= mem_addr;
        held_size_q  <= mem_size;
        held_wdata_q <= mem_wdata;
      end
      if (mem_ack) held_req_q <= 1'b0;
    end
  end

  task automatic begin_case;
    @(negedge clk);
    rst = 1'b1;
    repeat (3) @(posedge clk);
    #1;
    for (int unsigned i = 0; i < 512; i++) begin
      u_mem.mem[i] = 16'h0300;
    end
  endtask

  task automatic build_program(
      input instr_word_t opcode,
      input logic hrev,
      input logic vrev,
      input logic [DATA_WIDTH-1:0] daddr,
      input logic [15:0] dx,
      input logic [15:0] dy,
      input logic [DATA_WIDTH-1:0] wstart,
      input logic [DATA_WIDTH-1:0] wend
  );
    int unsigned p;
    logic [DATA_WIDTH-1:0] control;

    control = (DATA_WIDTH'(1) << CTRL_W_LO)
            | (DATA_WIDTH'(hrev) << CTRL_PBH_BIT)
            | (DATA_WIDTH'(vrev) << CTRL_PBV_BIT);

    p = 0;
    p = place_word(p, setf_enc(5'd16));
    p = place_movi_il(p, 4'd0, 32'd8);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(
        p, 4'd0, DATA_WIDTH'(1) << DPYCTL_SRT_BIT);
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_movi_il(p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_movi_il(p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il(p, 4'd0, control);
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_movi_il_b(p, 4'd0, SADDR_SEED);
    p = place_movi_il_b(p, 4'd1, 32'h0000_0080);
    p = place_movi_il_b(p, 4'd2, daddr);
    p = place_movi_il_b(p, 4'd3, 32'h0000_0080);
    p = place_movi_il_b(p, 4'd4, 32'h0000_1000);
    p = place_movi_il_b(p, 4'd5, wstart);
    p = place_movi_il_b(p, 4'd6, wend);
    p = place_movi_il_b(p, 4'd7, {dy, dx});
    p = place_movi_il_b(p, 4'd8, 32'h0000_0011);
    p = place_movi_il_b(p, 4'd9, 32'h0000_00EE);
    p = place_movi_il(p, 4'd14, ST_SEED);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, opcode);
    p = place_word(p, getst_enc(4'd13));
    p = place_word(p, 16'hC0FF);
  endtask

  task automatic launch_and_wait(input string label);
    logic reached_loop;
    reached_loop = 1'b0;
    @(negedge clk);
    rst = 1'b0;
    begin : wait_cycles
      for (int unsigned cycle = 0; cycle < 10000; cycle++) begin
        @(posedge clk);
        #1;
        if ((state_w == CORE_EXECUTE) && (instr_w == 16'hC0FF)) begin
          reached_loop = 1'b1;
          disable wait_cycles;
        end
      end
    end
    if (!reached_loop) begin
      $display("TEST_RESULT: FAIL: %s did not complete", label);
      failures++;
    end
  endtask

  task automatic run_case(
      input instr_word_t opcode,
      input logic hrev,
      input logic vrev,
      input logic [DATA_WIDTH-1:0] daddr,
      input logic [15:0] dx,
      input logic [15:0] dy,
      input logic [DATA_WIDTH-1:0] wstart,
      input logic [DATA_WIDTH-1:0] wend,
      input logic hit,
      input logic empty,
      input logic [DATA_WIDTH-1:0] expected_daddr,
      input logic [DATA_WIDTH-1:0] expected_dydx,
      input string label
  );
    logic expected_v;
    logic expected_wvp;
    logic [DATA_WIDTH-1:0] expected_st;

    begin_case();
    build_program(opcode, hrev, vrev, daddr, dx, dy, wstart, wend);
    launch_and_wait(label);

    expected_v   = empty ? 1'b0 : !hit;
    expected_wvp = !empty && hit;
    expected_st  = ST_SEED;
    expected_st[ST_V_BIT] = expected_v;

    if (u_core.u_regfile.b_regs[B_DADDR_IDX] !== expected_daddr) begin
      $display("TEST_RESULT: FAIL: %s DADDR expected=%08h actual=%08h",
               label, expected_daddr,
               u_core.u_regfile.b_regs[B_DADDR_IDX]);
      failures++;
    end
    if (u_core.u_regfile.b_regs[B_DYDX_IDX] !== expected_dydx) begin
      $display("TEST_RESULT: FAIL: %s DYDX expected=%08h actual=%08h",
               label, expected_dydx,
               u_core.u_regfile.b_regs[B_DYDX_IDX]);
      failures++;
    end
    if ((opcode != 16'h0FE0)
        && (u_core.u_regfile.b_regs[B_SADDR_IDX] !== SADDR_SEED)) begin
      $display("TEST_RESULT: FAIL: %s changed SADDR to %08h",
               label, u_core.u_regfile.b_regs[B_SADDR_IDX]);
      failures++;
    end
    if (u_core.u_regfile.a_regs[13] !== expected_st) begin
      $display("TEST_RESULT: FAIL: %s ST expected=%08h actual=%08h",
               label, expected_st, u_core.u_regfile.a_regs[13]);
      failures++;
    end
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND][INT_WV_BIT]
        !== expected_wvp) begin
      $display("TEST_RESULT: FAIL: %s WVP expected=%0b actual=%0b",
               label, expected_wvp,
               u_core.u_io_regs.io_reg[IO_IDX_INTPEND][INT_WV_BIT]);
      failures++;
    end
    if (graphics_requests != 0) begin
      $display("TEST_RESULT: FAIL: %s issued %0d graphics request(s)",
               label, graphics_requests);
      failures++;
    end
    if (protocol_error || !saw_wait) begin
      $display("TEST_RESULT: FAIL: %s stall error=%0b saw_wait=%0b",
               label, protocol_error, saw_wait);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: %s raised illegal opcode", label);
      failures++;
    end
  endtask

  initial begin : main
    failures = 0;

    // FILL XY: complete geometry taxonomy and PB isolation.
    run_case(16'h0FE0, 1, 1, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000B_000C, 32'h0003_0003, "FILL partial PB ignored");
    run_case(16'h0FE0, 0, 0, 32'h000A_000A, 3, 3,
             32'h001E_001E, 32'h0020_0020, 0, 0,
             32'h000A_000A, 32'h0003_0003, "FILL disjoint");
    run_case(16'h0FE0, 0, 0, 32'h0006_0005, 2, 3,
             32'h0000_0000, 32'h0014_0014, 1, 0,
             32'h0006_0005, 32'h0003_0002, "FILL contained");
    run_case(16'h0FE0, 0, 0, 32'h0006_0005, 10, 10,
             32'h0009_0008, 32'h000B_0009, 1, 0,
             32'h0009_0008, 32'h0003_0002, "FILL enclosing");
    run_case(16'h0FE0, 0, 0, 32'h000A_000A, 3, 3,
             32'h000C_000C, 32'h0014_0014, 1, 0,
             32'h000C_000C, 32'h0001_0001, "FILL boundary pixel");
    run_case(16'h0FE0, 0, 0, 32'h000A_000A, 3, 3,
             32'h0000_000C, 32'h0014_000B, 0, 0,
             32'h000A_000A, 32'h0003_0003, "FILL empty-X window");
    run_case(16'h0FE0, 0, 0, 32'h000A_000A, 0, 3,
             32'h0000_0000, 32'h0014_0014, 0, 1,
             32'h000A_000A, 32'h0003_0000, "FILL DX zero");
    run_case(16'h0FE0, 0, 0, 32'h000A_000A, 3, 0,
             32'h0000_0000, 32'h0014_0014, 0, 1,
             32'h000A_000A, 32'h0000_0003, "FILL DY zero");

    // Binary-to-XY always returns the lowest-address common corner.
    run_case(16'h0FA0, 0, 0, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000B_000C, 32'h0003_0003, "B,XY PB00");
    run_case(16'h0FA0, 1, 1, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000B_000C, 32'h0003_0003, "B,XY PB11 ignored");
    run_case(16'h0FA0, 1, 1, 32'h000A_000A, 3, 3,
             32'h001E_001E, 32'h0020_0020, 0, 0,
             32'h000A_000A, 32'h0003_0003, "B,XY disjoint");
    run_case(16'h0FA0, 1, 1, 32'h000A_000A, 0, 3,
             32'h0000_0000, 32'h0014_0014, 0, 1,
             32'h000A_000A, 32'h0003_0000, "B,XY empty");

    // Direction changes only which corner encodes the L,XY intersection.
    run_case(16'h0F20, 0, 0, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000B_000C, 32'h0003_0003, "L,XY PB00");
    run_case(16'h0F20, 1, 0, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000B_000E, 32'h0003_0003, "L,XY PB10");
    run_case(16'h0F20, 0, 1, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000D_000C, 32'h0003_0003, "L,XY PB01");
    run_case(16'h0F20, 1, 1, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000D_000E, 32'h0003_0003, "L,XY PB11");
    run_case(16'h0F20, 0, 0, 32'h000A_000A, 3, 3,
             32'h001E_001E, 32'h0020_0020, 0, 0,
             32'h000A_000A, 32'h0003_0003, "L,XY disjoint");
    run_case(16'h0F20, 0, 1, 32'h000A_000A, 3, 0,
             32'h0000_0000, 32'h0014_0014, 0, 1,
             32'h000A_000A, 32'h0000_0003, "L,XY empty");

    // XY,XY uses the same directional result after geometry is intersected.
    run_case(16'h0F60, 0, 0, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000B_000C, 32'h0003_0003, "XY,XY PB00");
    run_case(16'h0F60, 1, 0, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000B_000E, 32'h0003_0003, "XY,XY PB10");
    run_case(16'h0F60, 0, 1, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000D_000C, 32'h0003_0003, "XY,XY PB01");
    run_case(16'h0F60, 1, 1, 32'h000A_000A, 5, 4,
             32'h000B_000C, 32'h000F_0014, 1, 0,
             32'h000D_000E, 32'h0003_0003, "XY,XY PB11");
    run_case(16'h0F60, 1, 1, 32'h0006_0005, 2, 3,
             32'h0000_0000, 32'h0014_0014, 1, 0,
             32'h0008_0006, 32'h0003_0002, "XY,XY contained reverse");
    run_case(16'h0F60, 1, 1, 32'h0006_0005, 10, 10,
             32'h0009_0008, 32'h000B_0009, 1, 0,
             32'h000B_0009, 32'h0003_0002, "XY,XY enclosing reverse");
    run_case(16'h0F60, 1, 1, 32'h000A_000A, 3, 3,
             32'h000C_000C, 32'h0014_0014, 1, 0,
             32'h000C_000C, 32'h0001_0001, "XY,XY boundary reverse");
    run_case(16'h0F60, 1, 1, 32'h000A_000A, 3, 3,
             32'h001E_001E, 32'h0020_0020, 0, 0,
             32'h000A_000A, 32'h0003_0003, "XY,XY disjoint");
    run_case(16'h0F60, 1, 1, 32'h000A_000A, 3, 3,
             32'h000C_0000, 32'h000B_0014, 0, 0,
             32'h000A_000A, 32'h0003_0003, "XY,XY empty-Y window");
    run_case(16'h0F60, 1, 1, 32'h000A_000A, 0, 3,
             32'h0000_0000, 32'h0014_0014, 0, 1,
             32'h000A_000A, 32'h0003_0000, "XY,XY empty");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (W=1 common rectangles and no pixel traffic)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #60_000_000;
    $display("TEST_RESULT: FAIL: tb_window_common_rect hard timeout");
    $fatal(1);
  end

endmodule : tb_window_common_rect
