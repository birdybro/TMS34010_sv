// -----------------------------------------------------------------------------
// tb_pixblt_direction.sv
//
// Task 0163: PBH/PBV traversal and corner adjustment for PIXBLT.
//
// Coverage:
//   * all four PBH/PBV combinations for L,L; L,XY; XY,L; and XY,XY;
//   * software-supplied L,L corners versus automatic mixed/XY corners;
//   * PSIZE 1/2/4/8/16, non-power-of-two linear pitches, one-pixel/one-row
//     edges, and exact completion SADDR/DADDR;
//   * B,L and B,XY isolation from PBH/PBV;
//   * safe forward and reverse copies between overlapping framebuffer spans;
//   * three extra physical-word waits plus held-request monitoring.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixblt_direction;
  import tms34010_pkg::*;

  localparam logic [DATA_WIDTH-1:0] OFFSET_VAL = 32'h0000_1000;
  localparam logic [DATA_WIDTH-1:0] SRC_TOP    = 32'h0000_1000;
  localparam logic [DATA_WIDTH-1:0] DST_TOP    = 32'h0000_3000;
  localparam logic [DATA_WIDTH-1:0] SRC_PITCH2 = 32'h0000_0100;
  localparam logic [DATA_WIDTH-1:0] DST_PITCH2 = 32'h0000_0200;
  localparam logic [DATA_WIDTH-1:0] SRC_ODD    = 32'h0000_00B0;
  localparam logic [DATA_WIDTH-1:0] DST_ODD    = 32'h0000_00D0;

  localparam logic [31:0] A_CONTROL =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONTROL) << 4);
  localparam logic [31:0] A_CONVSP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVSP) << 4);
  localparam logic [31:0] A_CONVDP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVDP) << 4);
  localparam logic [31:0] A_PSIZE =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PSIZE) << 4);

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
    .DEPTH_WORDS(2048),
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

  function automatic int unsigned psize_shift(input int unsigned psize);
    unique case (psize)
      1:       psize_shift = 0;
      2:       psize_shift = 1;
      4:       psize_shift = 2;
      8:       psize_shift = 3;
      default: psize_shift = 4;
    endcase
  endfunction

  task automatic write_field(
      input logic [DATA_WIDTH-1:0] bit_addr,
      input int unsigned size,
      input logic [DATA_WIDTH-1:0] value
  );
    int unsigned absolute_bit;
    for (int unsigned bit_index = 0; bit_index < size; bit_index++) begin
      absolute_bit = bit_addr + bit_index;
      u_mem.mem[absolute_bit >> 4][absolute_bit & 15] = value[bit_index];
    end
  endtask

  function automatic logic [DATA_WIDTH-1:0] read_field(
      input logic [DATA_WIDTH-1:0] bit_addr,
      input int unsigned size
  );
    logic [DATA_WIDTH-1:0] value;
    int unsigned absolute_bit;
    value = '0;
    for (int unsigned bit_index = 0; bit_index < size; bit_index++) begin
      absolute_bit = bit_addr + bit_index;
      value[bit_index] = u_mem.mem[absolute_bit >> 4][absolute_bit & 15];
    end
    read_field = value;
  endfunction

  int unsigned failures;
  logic protocol_error;
  logic saw_graphics_wait;
  logic held_req_q;
  logic held_we_q;
  logic [ADDR_WIDTH-1:0]       held_addr_q;
  logic [FIELD_SIZE_WIDTH-1:0] held_size_q;
  logic [DATA_WIDTH-1:0]       held_wdata_q;

  always @(posedge clk) begin
    if (rst) begin
      protocol_error    <= 1'b0;
      saw_graphics_wait <= 1'b0;
      held_req_q        <= 1'b0;
      held_we_q         <= 1'b0;
      held_addr_q       <= '0;
      held_size_q       <= '0;
      held_wdata_q      <= '0;
    end else begin
      if ((state_w == CORE_PBLT) && mem_req && !mem_ack) begin
        saw_graphics_wait <= 1'b1;
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
    for (int unsigned i = 0; i < 2048; i++) begin
      u_mem.mem[i] = 16'h0300;
    end
  endtask

  task automatic build_program(
      input instr_word_t opcode,
      input int unsigned psize,
      input logic hrev,
      input logic vrev,
      input logic [DATA_WIDTH-1:0] source_raw,
      input logic [DATA_WIDTH-1:0] sptch,
      input logic [DATA_WIDTH-1:0] dest_raw,
      input logic [DATA_WIDTH-1:0] dptch,
      input int unsigned dx,
      input int unsigned dy
  );
    int unsigned p;
    logic [DATA_WIDTH-1:0] control;
    control = (DATA_WIDTH'(hrev) << CTRL_PBH_BIT)
            | (DATA_WIDTH'(vrev) << CTRL_PBV_BIT);

    p = 0;
    p = place_word(p, setf_enc(5'd16));
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(psize));
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, 32'h0000_0017);
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_movi_il(p, 4'd0, 32'h0000_0016);
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il(p, 4'd0, control);
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_movi_il_b(p, 4'd0, source_raw);
    p = place_movi_il_b(p, 4'd1, sptch);
    p = place_movi_il_b(p, 4'd2, dest_raw);
    p = place_movi_il_b(p, 4'd3, dptch);
    p = place_movi_il_b(p, 4'd4, OFFSET_VAL);
    p = place_movi_il_b(p, 4'd7, {16'(dy), 16'(dx)});
    p = place_movi_il_b(p, 4'd8, 32'h0000_0003);
    p = place_movi_il_b(p, 4'd9, 32'h0000_000E);
    p = place_word(p, opcode);
    p = place_word(p, 16'hC0FF);
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
      $display("TEST_RESULT: FAIL: %s did not complete", label);
      failures++;
    end
  endtask

  task automatic check_common(input string label);
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: %s raised illegal opcode", label);
      failures++;
    end
    if (protocol_error || !saw_graphics_wait) begin
      $display("TEST_RESULT: FAIL: %s stall contract error=%0b saw_wait=%0b",
               label, protocol_error, saw_graphics_wait);
      failures++;
    end
  endtask

  task automatic run_direction_case(
      input instr_word_t opcode,
      input logic hrev,
      input logic vrev,
      input int unsigned psize,
      input int unsigned dx,
      input int unsigned dy,
      input string label
  );
    logic src_xy;
    logic dst_xy;
    logic is_ll;
    logic [DATA_WIDTH-1:0] sptch;
    logic [DATA_WIDTH-1:0] dptch;
    logic [DATA_WIDTH-1:0] source_raw;
    logic [DATA_WIDTH-1:0] dest_raw;
    logic [DATA_WIDTH-1:0] expected_saddr;
    logic [DATA_WIDTH-1:0] expected_daddr;
    logic [15:0] dest_x;
    logic [DATA_WIDTH-1:0] expected_pixel;
    logic [DATA_WIDTH-1:0] actual_pixel;

    is_ll  = (opcode == 16'h0F00);
    src_xy = (opcode == 16'h0F40) || (opcode == 16'h0F60);
    dst_xy = (opcode == 16'h0F20) || (opcode == 16'h0F60);

    sptch = is_ll ? SRC_ODD
           : (!src_xy && !vrev) ? SRC_ODD : SRC_PITCH2;
    dptch = is_ll ? DST_ODD
           : (!dst_xy && !vrev) ? DST_ODD : DST_PITCH2;
    dest_x = 16'(32'h0000_2000 >> psize_shift(psize));

    if (is_ll) begin
      source_raw = SRC_TOP
                 + (vrev ? DATA_WIDTH'((dy - 1) * sptch) : 32'd0)
                 + (hrev ? DATA_WIDTH'(dx * psize) : 32'd0);
      dest_raw = DST_TOP
               + (vrev ? DATA_WIDTH'((dy - 1) * dptch) : 32'd0)
               + (hrev ? DATA_WIDTH'(dx * psize) : 32'd0);
      expected_saddr = source_raw + DATA_WIDTH'(dy * sptch);
      expected_daddr = dest_raw   + DATA_WIDTH'(dy * dptch);
    end else begin
      source_raw = src_xy ? 32'h0000_0000 : SRC_TOP;
      dest_raw   = dst_xy ? {16'h0000, dest_x} : DST_TOP;
      expected_saddr = SRC_TOP + DATA_WIDTH'(dy * sptch);
      expected_daddr = DST_TOP + DATA_WIDTH'(dy * dptch);
    end

    begin_case();
    build_program(opcode, psize, hrev, vrev, source_raw, sptch,
                  dest_raw, dptch, dx, dy);
    for (int unsigned row = 0; row < dy; row++) begin
      for (int unsigned col = 0; col < dx; col++) begin
        write_field(SRC_TOP + DATA_WIDTH'(row * sptch)
                    + DATA_WIDTH'(col * psize),
                    psize, DATA_WIDTH'(1 + row * dx + col));
        write_field(DST_TOP + DATA_WIDTH'(row * dptch)
                    + DATA_WIDTH'(col * psize),
                    psize, '0);
      end
    end

    launch_and_wait(label);

    for (int unsigned row = 0; row < dy; row++) begin
      for (int unsigned col = 0; col < dx; col++) begin
        expected_pixel = DATA_WIDTH'(1 + row * dx + col);
        actual_pixel = read_field(DST_TOP + DATA_WIDTH'(row * dptch)
                                  + DATA_WIDTH'(col * psize), psize);
        if (actual_pixel !== (expected_pixel
                              & ((32'd1 << psize) - 32'd1))) begin
          $display("TEST_RESULT: FAIL: %s pixel[%0d,%0d] expected=%08h actual=%08h",
                   label, row, col, expected_pixel, actual_pixel);
          failures++;
        end
      end
    end
    if (u_core.u_regfile.b_regs[0] !== expected_saddr
        || u_core.u_regfile.b_regs[2] !== expected_daddr) begin
      $display("TEST_RESULT: FAIL: %s context S=%08h/%08h D=%08h/%08h",
               label, u_core.u_regfile.b_regs[0], expected_saddr,
               u_core.u_regfile.b_regs[2], expected_daddr);
      failures++;
    end
    check_common(label);
  endtask

  task automatic run_binary_isolation(
      input instr_word_t opcode,
      input string label
  );
    logic dst_xy;
    logic [DATA_WIDTH-1:0] dest_raw;
    logic [DATA_WIDTH-1:0] actual_pixel;
    logic [15:0] dest_x;
    dest_x = 16'(32'h0000_2000 >> 2);
    dst_xy = (opcode == 16'h0FA0);
    dest_raw = dst_xy ? {16'h0000, dest_x} : DST_TOP;

    begin_case();
    build_program(opcode, 4, 1'b1, 1'b1, SRC_TOP, 32'h0000_0070,
                  dest_raw, dst_xy ? DST_PITCH2 : DST_ODD, 3, 2);
    // PBH/PBV must be ignored: consume each row left-to-right, top-to-bottom.
    for (int unsigned row = 0; row < 2; row++) begin
      for (int unsigned col = 0; col < 3; col++) begin
        write_field(SRC_TOP + DATA_WIDTH'(row * 32'h70 + col), 1,
                    DATA_WIDTH'((row + col) & 1));
        write_field(DST_TOP
                    + DATA_WIDTH'(row * (dst_xy ? DST_PITCH2 : DST_ODD))
                    + DATA_WIDTH'(col * 4), 4, '0);
      end
    end
    launch_and_wait(label);
    for (int unsigned row = 0; row < 2; row++) begin
      for (int unsigned col = 0; col < 3; col++) begin
        actual_pixel = read_field(
            DST_TOP + DATA_WIDTH'(row * (dst_xy ? DST_PITCH2 : DST_ODD))
            + DATA_WIDTH'(col * 4), 4);
        if (actual_pixel !== ((((row + col) & 1) != 0) ? 32'hE : 32'h3)) begin
          $display("TEST_RESULT: FAIL: %s binary pixel[%0d,%0d]=%08h",
                   label, row, col, actual_pixel);
          failures++;
        end
      end
    end
    if (u_core.u_regfile.b_regs[0] !== (SRC_TOP + 32'h0000_00E0)
        || u_core.u_regfile.b_regs[2]
           !== (DST_TOP + (dst_xy ? 32'h0000_0400 : 32'h0000_01A0))) begin
      $display("TEST_RESULT: FAIL: %s PBH/PBV affected binary context", label);
      failures++;
    end
    check_common(label);
  endtask

  task automatic run_overlap_case(
      input logic reverse,
      input string label
  );
    localparam logic [DATA_WIDTH-1:0] OVERLAP_BASE = 32'h0000_1800;
    logic [DATA_WIDTH-1:0] source_top;
    logic [DATA_WIDTH-1:0] dest_top;
    logic [DATA_WIDTH-1:0] source_raw;
    logic [DATA_WIDTH-1:0] dest_raw;
    logic [DATA_WIDTH-1:0] actual_pixel;

    source_top = reverse ? OVERLAP_BASE : OVERLAP_BASE + 32'd8;
    dest_top   = reverse ? OVERLAP_BASE + 32'd8 : OVERLAP_BASE;
    source_raw = source_top + (reverse ? 32'd48 : 32'd0);
    dest_raw   = dest_top   + (reverse ? 32'd48 : 32'd0);

    begin_case();
    build_program(16'h0F00, 8, reverse, 1'b0,
                  source_raw, 32'h0000_0100,
                  dest_raw, 32'h0000_0100, 6, 1);
    for (int unsigned col = 0; col < 7; col++) begin
      write_field(OVERLAP_BASE + DATA_WIDTH'(col * 8), 8, 32'd0);
    end
    for (int unsigned col = 0; col < 6; col++) begin
      write_field(source_top + DATA_WIDTH'(col * 8), 8,
                  DATA_WIDTH'(8'h40 + col));
    end
    launch_and_wait(label);
    for (int unsigned col = 0; col < 6; col++) begin
      actual_pixel = read_field(dest_top + DATA_WIDTH'(col * 8), 8);
      if (actual_pixel !== DATA_WIDTH'(8'h40 + col)) begin
        $display("TEST_RESULT: FAIL: %s overlap pixel[%0d]=%08h",
                 label, col, actual_pixel);
        failures++;
      end
    end
    check_common(label);
  endtask

  initial begin : main
    failures = 0;

    // Every full-color addressing form and direction.
    run_direction_case(16'h0F00, 0, 0, 1, 3, 2, "L,L PBH0 PBV0");
    run_direction_case(16'h0F00, 1, 0, 2, 3, 2, "L,L PBH1 PBV0");
    run_direction_case(16'h0F00, 0, 1, 4, 3, 2, "L,L PBH0 PBV1");
    run_direction_case(16'h0F00, 1, 1, 8, 3, 2, "L,L PBH1 PBV1");

    run_direction_case(16'h0F20, 0, 0, 16, 3, 2, "L,XY PBH0 PBV0");
    run_direction_case(16'h0F20, 1, 0, 8, 3, 2, "L,XY PBH1 PBV0");
    run_direction_case(16'h0F20, 0, 1, 4, 3, 2, "L,XY PBH0 PBV1");
    run_direction_case(16'h0F20, 1, 1, 2, 3, 2, "L,XY PBH1 PBV1");

    run_direction_case(16'h0F40, 0, 0, 1, 3, 2, "XY,L PBH0 PBV0");
    run_direction_case(16'h0F40, 1, 0, 2, 3, 2, "XY,L PBH1 PBV0");
    run_direction_case(16'h0F40, 0, 1, 8, 3, 2, "XY,L PBH0 PBV1");
    run_direction_case(16'h0F40, 1, 1, 16, 3, 2, "XY,L PBH1 PBV1");

    run_direction_case(16'h0F60, 0, 0, 4, 3, 2, "XY,XY PBH0 PBV0");
    run_direction_case(16'h0F60, 1, 0, 8, 3, 2, "XY,XY PBH1 PBV0");
    run_direction_case(16'h0F60, 0, 1, 16, 3, 2, "XY,XY PBH0 PBV1");
    run_direction_case(16'h0F60, 1, 1, 1, 3, 2, "XY,XY PBH1 PBV1");

    // Degenerate rows/columns in each direction.
    run_direction_case(16'h0F60, 0, 0, 16, 1, 1, "edge 1x1 forward");
    run_direction_case(16'h0F60, 1, 0, 4, 1, 3, "edge one-column PBH1");
    run_direction_case(16'h0F60, 0, 1, 2, 3, 1, "edge one-row PBV1");
    run_direction_case(16'h0F60, 1, 1, 8, 1, 1, "edge 1x1 reverse");

    run_binary_isolation(16'h0F80, "B,L ignores PBH/PBV");
    run_binary_isolation(16'h0FA0, "B,XY ignores PBH/PBV");

    run_overlap_case(1'b0, "forward safe overlap");
    run_overlap_case(1'b1, "reverse safe overlap");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (PIXBLT PBH/PBV direction and overlap)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #15_000_000;
    $display("TEST_RESULT: FAIL: tb_pixblt_direction hard timeout");
    $fatal(1);
  end

endmodule : tb_pixblt_direction
