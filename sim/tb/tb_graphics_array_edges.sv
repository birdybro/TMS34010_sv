// -----------------------------------------------------------------------------
// tb_graphics_array_edges.sv
//
// Task 0162 coverage for the architectural edges shared by FILL and PIXBLT:
//   * DX=0 and DY=0 are empty arrays for both FILL forms and all six PIXBLTs.
//   * Empty arrays complete without graphics memory traffic, flag changes, or
//     implied-register writeback.
//   * FILL retains its final-row next-X DADDR convention.
//   * PIXBLT publishes the first source/destination pixel of the hypothetical
//     next row, including binary-source and XY-converted forms.
//
// Every case runs through the synthesizable field sequencer with three
// additional physical-word wait cycles.  A protocol monitor also proves the
// core holds every outstanding field request stable through acknowledgement.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_graphics_array_edges;
  import tms34010_pkg::*;

  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hF000_0010;
  localparam logic [DATA_WIDTH-1:0] LINEAR_SRC = 32'h0000_1800;
  localparam logic [DATA_WIDTH-1:0] LINEAR_DST = 32'h0000_2000;
  localparam logic [DATA_WIDTH-1:0] OFFSET_VAL = LINEAR_SRC;

  localparam logic [31:0] A_PSIZE =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PSIZE) << 4);
  localparam logic [31:0] A_CONVSP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVSP) << 4);
  localparam logic [31:0] A_CONVDP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVDP) << 4);

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req;
  logic                        mem_we;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata;
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
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_srt(),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack), .state_o(state_w),
    .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w),
    .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1),
    .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0),
    .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00),
    .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(),
    .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(),
    .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(),
    .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(),
    .video_vsync_o(), .video_hblank_o(), .video_vblank_o(),
    .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(),
    .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(
    .DEPTH_WORDS(1024),
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

  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic fe,
                                           input logic f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9)
             | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000
             | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
  endfunction

  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction

  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
  endfunction

  function automatic int unsigned place_word(input int unsigned p,
                                             input instr_word_t w);
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

  int unsigned failures;
  int unsigned graphics_req_cycles;
  int unsigned graphics_mem_acks;
  logic        saw_graphics_wait;
  logic        protocol_error;
  logic        held_req_q;
  logic        held_we_q;
  logic [ADDR_WIDTH-1:0]       held_addr_q;
  logic [FIELD_SIZE_WIDTH-1:0] held_size_q;
  logic [DATA_WIDTH-1:0]       held_wdata_q;

  // End-to-end request stability and graphics-traffic accounting.
  always @(posedge clk) begin
    if (rst) begin
      graphics_req_cycles <= 0;
      graphics_mem_acks    <= 0;
      saw_graphics_wait    <= 1'b0;
      protocol_error       <= 1'b0;
      held_req_q           <= 1'b0;
      held_we_q            <= 1'b0;
      held_addr_q          <= '0;
      held_size_q          <= '0;
      held_wdata_q         <= '0;
    end else begin
      if (((state_w == CORE_FILL) || (state_w == CORE_PBLT)) && mem_req) begin
        graphics_req_cycles <= graphics_req_cycles + 1;
        if (mem_ack) graphics_mem_acks <= graphics_mem_acks + 1;
        if (!mem_ack) saw_graphics_wait <= 1'b1;
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
    for (int unsigned i = 0; i < 1024; i++) begin
      u_mem.mem[i] = 16'h0300;
    end
    // Distinct source data and destination sentinels.
    for (int unsigned i = 360; i < 480; i++) begin
      u_mem.mem[i] = 16'(16'h5100 + i);
    end
    for (int unsigned i = 500; i < 580; i++) begin
      u_mem.mem[i] = 16'hA55A;
    end
  endtask

  task automatic launch_and_wait(input string label);
    logic reached_loop;
    reached_loop = 1'b0;
    @(negedge clk);
    rst = 1'b0;
    begin : wait_cycles
      for (int unsigned cycle = 0; cycle < 8000; cycle++) begin
        @(posedge clk);
        #1;
        if ((state_w == CORE_EXECUTE) && (instr_w == 16'hC0FF)) begin
          reached_loop = 1'b1;
          disable wait_cycles;
        end
      end
    end
    if (!reached_loop) begin
      $display("TEST_RESULT: FAIL: %s did not complete promptly", label);
      failures++;
    end
  endtask

  task automatic check_common(input string label);
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: %s raised illegal opcode", label);
      failures++;
    end
    if (protocol_error) begin
      $display("TEST_RESULT: FAIL: %s changed an outstanding request", label);
      failures++;
    end
  endtask

  task automatic run_empty_case(
      input instr_word_t opcode,
      input logic [15:0] dx,
      input logic [15:0] dy,
      input string label
  );
    int unsigned p;
    logic [DATA_WIDTH-1:0] dims;
    logic [DATA_WIDTH-1:0] source_raw;
    logic [DATA_WIDTH-1:0] dest_raw;

    dims       = {dy, dx};
    source_raw = 32'h8123_4567;
    dest_raw   = 32'h9234_5678;
    begin_case();

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd0, 32'd8);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il_b(p, 4'd0, source_raw);
    p = place_movi_il_b(p, 4'd1, 32'hFFFF_FFA0);
    p = place_movi_il_b(p, 4'd2, dest_raw);
    p = place_movi_il_b(p, 4'd3, 32'h0000_00D0);
    p = place_movi_il_b(p, 4'd4, OFFSET_VAL);
    p = place_movi_il_b(p, 4'd7, dims);
    p = place_movi_il_b(p, 4'd8, 32'h0000_0033);
    p = place_movi_il_b(p, 4'd9, 32'h0000_00CC);
    p = place_movi_il(p, 4'd14, ST_SEED);
    p = place_word(p, putst_enc(4'd14));
    p = place_word(p, opcode);
    p = place_word(p, getst_enc(4'd13));
    p = place_word(p, 16'hC0FF);

    launch_and_wait(label);

    if (graphics_req_cycles != 0 || graphics_mem_acks != 0) begin
      $display("TEST_RESULT: FAIL: %s generated graphics traffic cycles=%0d acks=%0d",
               label, graphics_req_cycles, graphics_mem_acks);
      failures++;
    end
    if (u_core.u_regfile.b_regs[0] !== source_raw
        || u_core.u_regfile.b_regs[2] !== dest_raw
        || u_core.u_regfile.b_regs[7] !== dims) begin
      $display("TEST_RESULT: FAIL: %s changed implied B registers", label);
      failures++;
    end
    if (u_core.u_regfile.a_regs[13] !== ST_SEED) begin
      $display("TEST_RESULT: FAIL: %s changed ST expected=%08h actual=%08h",
               label, ST_SEED, u_core.u_regfile.a_regs[13]);
      failures++;
    end
    if (u_mem.mem[512] !== 16'hA55A || u_mem.mem[560] !== 16'hA55A) begin
      $display("TEST_RESULT: FAIL: %s changed destination sentinels", label);
      failures++;
    end
    check_common(label);
  endtask

  task automatic run_terminal_case(
      input instr_word_t opcode,
      input int unsigned psize,
      input logic [DATA_WIDTH-1:0] sptch,
      input logic [DATA_WIDTH-1:0] dptch,
      input string label
  );
    int unsigned p;
    logic is_fill;
    logic src_xy;
    logic dst_xy;
    logic [DATA_WIDTH-1:0] source_raw;
    logic [DATA_WIDTH-1:0] dest_raw;
    logic [DATA_WIDTH-1:0] expected_source;
    logic [DATA_WIDTH-1:0] expected_dest;
    logic [15:0] dest_x;

    is_fill = (opcode == 16'h0FC0) || (opcode == 16'h0FE0);
    src_xy  = (opcode == 16'h0F40) || (opcode == 16'h0F60);
    dst_xy  = (opcode == 16'h0F20) || (opcode == 16'h0F60)
           || (opcode == 16'h0FA0) || (opcode == 16'h0FE0);
    dest_x  = 16'(32'h0000_0800 / psize);
    source_raw = src_xy ? 32'h0000_0000 : LINEAR_SRC;
    dest_raw   = dst_xy ? {16'h0000, dest_x} : LINEAR_DST;

    expected_source = LINEAR_SRC + (sptch << 1);
    expected_dest = is_fill
                  ? LINEAR_DST + dptch + DATA_WIDTH'(3 * psize)
                  : LINEAR_DST + (dptch << 1);

    begin_case();
    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(psize));
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il_b(p, 4'd0, source_raw);
    p = place_movi_il_b(p, 4'd1, sptch);
    p = place_movi_il_b(p, 4'd2, dest_raw);
    p = place_movi_il_b(p, 4'd3, dptch);
    p = place_movi_il_b(p, 4'd4, OFFSET_VAL);
    p = place_movi_il_b(p, 4'd7, 32'h0002_0003);
    p = place_movi_il_b(p, 4'd8, 32'h0000_0033);
    p = place_movi_il_b(p, 4'd9, 32'h0000_00CC);
    p = place_word(p, opcode);
    p = place_word(p, 16'hC0FF);

    launch_and_wait(label);

    if (is_fill) begin
      if (u_core.u_regfile.b_regs[2] !== expected_dest) begin
        $display("TEST_RESULT: FAIL: %s DADDR expected=%08h actual=%08h",
                 label, expected_dest, u_core.u_regfile.b_regs[2]);
        failures++;
      end
    end else begin
      if (u_core.u_regfile.b_regs[0] !== expected_source
          || u_core.u_regfile.b_regs[2] !== expected_dest) begin
        $display("TEST_RESULT: FAIL: %s context S=%08h/%08h D=%08h/%08h",
                 label, u_core.u_regfile.b_regs[0], expected_source,
                 u_core.u_regfile.b_regs[2], expected_dest);
        failures++;
      end
    end
    if ((graphics_mem_acks == 0) || !saw_graphics_wait) begin
      $display("TEST_RESULT: FAIL: %s did not exercise stalled graphics accesses",
               label);
      failures++;
    end
    check_common(label);
  endtask

  initial begin : main
    failures = 0;

    // Both empty dimensions for FILL L/XY and all full-color/binary PIXBLTs.
    run_empty_case(16'h0FC0, 16'd0, 16'd3, "FILL L DX=0");
    run_empty_case(16'h0FC0, 16'd3, 16'd0, "FILL L DY=0");
    run_empty_case(16'h0FE0, 16'd0, 16'd3, "FILL XY DX=0");
    run_empty_case(16'h0FE0, 16'd3, 16'd0, "FILL XY DY=0");
    run_empty_case(16'h0F00, 16'd0, 16'd3, "PIXBLT L,L DX=0");
    run_empty_case(16'h0F00, 16'd3, 16'd0, "PIXBLT L,L DY=0");
    run_empty_case(16'h0F20, 16'd0, 16'd3, "PIXBLT L,XY DX=0");
    run_empty_case(16'h0F20, 16'd3, 16'd0, "PIXBLT L,XY DY=0");
    run_empty_case(16'h0F40, 16'd0, 16'd3, "PIXBLT XY,L DX=0");
    run_empty_case(16'h0F40, 16'd3, 16'd0, "PIXBLT XY,L DY=0");
    run_empty_case(16'h0F60, 16'd0, 16'd3, "PIXBLT XY,XY DX=0");
    run_empty_case(16'h0F60, 16'd3, 16'd0, "PIXBLT XY,XY DY=0");
    run_empty_case(16'h0F80, 16'd0, 16'd3, "PIXBLT B,L DX=0");
    run_empty_case(16'h0F80, 16'd3, 16'd0, "PIXBLT B,L DY=0");
    run_empty_case(16'h0FA0, 16'd0, 16'd3, "PIXBLT B,XY DX=0");
    run_empty_case(16'h0FA0, 16'd3, 16'd0, "PIXBLT B,XY DY=0");

    // Multiple PSIZEs and positive, negative, and non-unit pitches under
    // injected physical-word stalls.
    run_terminal_case(16'h0FC0, 16, 32'h0000_0090, 32'hFFFF_FF50,
                      "FILL L negative pitch");
    run_terminal_case(16'h0FE0, 4, 32'h0000_0090, 32'h0000_00D0,
                      "FILL XY non-unit pitch");
    run_terminal_case(16'h0F00, 1, 32'hFFFF_FF60, 32'hFFFF_FF20,
                      "PIXBLT L,L negative pitch");
    run_terminal_case(16'h0F20, 2, 32'h0000_00A0, 32'h0000_00C0,
                      "PIXBLT L,XY");
    run_terminal_case(16'h0F40, 4, 32'h0000_00B0, 32'h0000_00D0,
                      "PIXBLT XY,L");
    run_terminal_case(16'h0F60, 8, 32'h0000_00A0, 32'h0000_00C0,
                      "PIXBLT XY,XY");
    run_terminal_case(16'h0F80, 16, 32'h0000_0090, 32'h0000_00D0,
                      "PIXBLT B,L");
    run_terminal_case(16'h0FA0, 8, 32'h0000_00B0, 32'h0000_00F0,
                      "PIXBLT B,XY");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (graphics empty arrays and terminal contexts)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #10_000_000;
    $display("TEST_RESULT: FAIL: tb_graphics_array_edges hard timeout");
    $fatal(1);
  end

endmodule : tb_graphics_array_edges
