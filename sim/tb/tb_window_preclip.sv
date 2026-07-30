// -----------------------------------------------------------------------------
// tb_window_preclip.sv
//
// Task 0165: true CONTROL.W=3 array preclipping.
//
// A software reference model intersects the destination array with the
// inclusive graphics window before execution.  The test compares every
// acknowledged graphics request against the resulting source/destination
// sequence, checks framebuffer correspondence, and verifies architectural
// completion context and status.
//
// Coverage:
//   * FILL XY and PIXBLT B,XY / L,XY / XY,XY;
//   * left/right/top/bottom and corner clips, containment, full exclusion,
//     and a one-pixel remainder;
//   * PSIZE 1/2/4/8/16 and independent legal source/destination pitches;
//   * all PBH/PBV combinations for both full-color PIXBLT forms and binary
//     isolation from PBH/PBV;
//   * exact request order, address, direction, size, write intent, and SRT;
//   * zero clipped/full-exclusion traffic, framebuffer alignment, final
//     B-register context, V-only status, no WVP, and three-cycle word waits.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_window_preclip;
  import tms34010_pkg::*;

  localparam int unsigned MEM_WORDS = 8192;
  localparam int unsigned MAX_REQUESTS = 128;

  localparam int unsigned KIND_FILL = 0;
  localparam int unsigned KIND_BXY  = 1;
  localparam int unsigned KIND_LXY  = 2;
  localparam int unsigned KIND_XYXY = 3;

  localparam logic [DATA_WIDTH-1:0] OFFSET_VAL = 32'h0000_4000;
  localparam logic [DATA_WIDTH-1:0] LINEAR_SRC = 32'h0000_C000;
  localparam logic [15:0] SRC_X = 16'd2;
  localparam logic [15:0] SRC_Y = 16'd3;
  localparam logic [15:0] DST_X = 16'd20;
  localparam logic [15:0] DST_Y = 16'd20;
  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hE000_0010;

  localparam logic [DATA_WIDTH-1:0] A_CONTROL =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONTROL) << 4);
  localparam logic [DATA_WIDTH-1:0] A_CONVSP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVSP) << 4);
  localparam logic [DATA_WIDTH-1:0] A_CONVDP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVDP) << 4);
  localparam logic [DATA_WIDTH-1:0] A_PSIZE =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PSIZE) << 4);
  localparam logic [DATA_WIDTH-1:0] A_PMASK =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PMASK) << 4);
  localparam logic [DATA_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_DPYCTL) << 4);

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
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_srt(mem_srt),
    .mem_iaq(), .mem_is_io(), .mem_io_we(), .mem_io_rdata(),
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
    .DEPTH_WORDS(MEM_WORDS),
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

  function automatic int unsigned pitch_shift(input int unsigned pitch);
    unique case (pitch)
      32:      pitch_shift = 5;
      64:      pitch_shift = 6;
      128:     pitch_shift = 7;
      256:     pitch_shift = 8;
      512:     pitch_shift = 9;
      1024:    pitch_shift = 10;
      default: pitch_shift = 0;
    endcase
  endfunction

  function automatic logic [DATA_WIDTH-1:0] field_mask(
      input int unsigned size
  );
    field_mask = (32'd1 << size) - 32'd1;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] uniform_color(
      input logic [DATA_WIDTH-1:0] pixel,
      input int unsigned size
  );
    logic [DATA_WIDTH-1:0] color;
    color = '0;
    for (int unsigned bit_offset = 0; bit_offset < 16;
         bit_offset += size)
      color |= (pixel & field_mask(size)) << bit_offset;
    uniform_color = color;
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

  logic [ADDR_WIDTH-1:0]       actual_addr [0:MAX_REQUESTS-1];
  logic                        actual_we   [0:MAX_REQUESTS-1];
  logic [FIELD_SIZE_WIDTH-1:0] actual_size [0:MAX_REQUESTS-1];
  logic                        actual_srt  [0:MAX_REQUESTS-1];
  logic [ADDR_WIDTH-1:0]       expected_addr [0:MAX_REQUESTS-1];
  logic                        expected_we   [0:MAX_REQUESTS-1];
  logic [FIELD_SIZE_WIDTH-1:0] expected_size [0:MAX_REQUESTS-1];
  logic                        expected_srt  [0:MAX_REQUESTS-1];

  int unsigned failures;
  int unsigned actual_count;
  int unsigned expected_count;
  logic protocol_error;
  logic saw_graphics_wait;
  logic held_req_q;
  logic held_we_q;
  logic [ADDR_WIDTH-1:0]       held_addr_q;
  logic [FIELD_SIZE_WIDTH-1:0] held_size_q;
  logic [DATA_WIDTH-1:0]       held_wdata_q;
  logic                        held_srt_q;

  function automatic logic graphics_state(input core_state_t state);
    graphics_state = (state == CORE_FILL) || (state == CORE_PBLT);
  endfunction

  always @(posedge clk) begin
    if (rst) begin
      actual_count      <= 0;
      protocol_error    <= 1'b0;
      saw_graphics_wait <= 1'b0;
      held_req_q        <= 1'b0;
      held_we_q         <= 1'b0;
      held_addr_q       <= '0;
      held_size_q       <= '0;
      held_wdata_q      <= '0;
      held_srt_q        <= 1'b0;
    end else begin
      if (graphics_state(state_w) && mem_req && mem_ack) begin
        if (actual_count < MAX_REQUESTS) begin
          actual_addr[actual_count] <= mem_addr;
          actual_we[actual_count]   <= mem_we;
          actual_size[actual_count] <= mem_size;
          actual_srt[actual_count]  <= mem_srt;
        end
        actual_count <= actual_count + 1;
      end
      if (graphics_state(state_w) && mem_req && !mem_ack) begin
        saw_graphics_wait <= 1'b1;
      end
      if (held_req_q
          && (!mem_req
              || (mem_we !== held_we_q)
              || (mem_addr !== held_addr_q)
              || (mem_size !== held_size_q)
              || (mem_wdata !== held_wdata_q)
              || (mem_srt !== held_srt_q))) begin
        protocol_error <= 1'b1;
      end
      if (mem_req && !mem_ack && !held_req_q) begin
        held_req_q   <= 1'b1;
        held_we_q    <= mem_we;
        held_addr_q  <= mem_addr;
        held_size_q  <= mem_size;
        held_wdata_q <= mem_wdata;
        held_srt_q   <= mem_srt;
      end
      if (mem_ack) held_req_q <= 1'b0;
    end
  end

  task automatic begin_case;
    @(negedge clk);
    rst = 1'b1;
    repeat (3) @(posedge clk);
    #1;
    for (int unsigned i = 0; i < MEM_WORDS; i++) begin
      u_mem.mem[i] = 16'h0300;
    end
    expected_count = 0;
  endtask

  task automatic append_request(
      input logic [DATA_WIDTH-1:0] addr,
      input logic we,
      input int unsigned size,
      input logic srt
  );
    if (expected_count >= MAX_REQUESTS) begin
      $display("TEST_RESULT: FAIL: reference request overflow");
      failures++;
    end else begin
      expected_addr[expected_count] = addr;
      expected_we[expected_count]   = we;
      expected_size[expected_count] = FIELD_SIZE_WIDTH'(size);
      expected_srt[expected_count]  = srt;
      expected_count++;
    end
  endtask

  task automatic build_program(
      input int unsigned kind,
      input int unsigned psize,
      input logic hrev,
      input logic vrev,
      input logic srt,
      input logic rmw,
      input int unsigned sptch,
      input int unsigned dptch,
      input int unsigned dx,
      input int unsigned dy,
      input int unsigned wx0,
      input int unsigned wy0,
      input int unsigned wx1,
      input int unsigned wy1
  );
    int unsigned p;
    instr_word_t opcode;
    logic [DATA_WIDTH-1:0] control;
    logic [DATA_WIDTH-1:0] source_raw;

    unique case (kind)
      KIND_FILL: opcode = 16'h0FE0;
      KIND_BXY:  opcode = 16'h0FA0;
      KIND_LXY:  opcode = 16'h0F20;
      default:   opcode = 16'h0F60;
    endcase
    source_raw = (kind == KIND_XYXY) ? {SRC_Y, SRC_X} : LINEAR_SRC;
    control = (DATA_WIDTH'(3) << CTRL_W_LO)
            | (DATA_WIDTH'(hrev) << CTRL_PBH_BIT)
            | (DATA_WIDTH'(vrev) << CTRL_PBV_BIT)
            | (rmw ? (DATA_WIDTH'(5'h0A) << CTRL_PPOP_LO) : 32'd0);

    p = 0;
    p = place_word(p, setf_enc(5'd16));
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(psize));
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(31 - pitch_shift(sptch)));
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(31 - pitch_shift(dptch)));
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il(p, 4'd0, control);
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_movi_il(p, 4'd0,
                      srt ? (DATA_WIDTH'(1) << DPYCTL_SRT_BIT) : 32'd0);
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_movi_il(p, 4'd0,
                      rmw ? uniform_color(32'h1, psize) : 32'd0);
    p = place_store_abs(p, 4'd0, A_PMASK);
    p = place_movi_il_b(p, 4'd0, source_raw);
    p = place_movi_il_b(p, 4'd1, DATA_WIDTH'(sptch));
    p = place_movi_il_b(p, 4'd2, {DST_Y, DST_X});
    p = place_movi_il_b(p, 4'd3, DATA_WIDTH'(dptch));
    p = place_movi_il_b(p, 4'd4, OFFSET_VAL);
    p = place_movi_il_b(p, 4'd5, {16'(wy0), 16'(wx0)});
    p = place_movi_il_b(p, 4'd6, {16'(wy1), 16'(wx1)});
    p = place_movi_il_b(p, 4'd7, {16'(dy), 16'(dx)});
    p = place_movi_il_b(p, 4'd8, uniform_color(32'h3, psize));
    p = place_movi_il_b(p, 4'd9, uniform_color(32'hAE, psize));
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
      for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
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

  task automatic compare_requests(input string label);
    if (actual_count != expected_count) begin
      $display("TEST_RESULT: FAIL: %s request count expected=%0d actual=%0d",
               label, expected_count, actual_count);
      failures++;
    end
    for (int unsigned i = 0;
         (i < actual_count) && (i < expected_count) && (i < MAX_REQUESTS);
         i++) begin
      if ((actual_addr[i] !== expected_addr[i])
          || (actual_we[i] !== expected_we[i])
          || (actual_size[i] !== expected_size[i])
          || (actual_srt[i] !== expected_srt[i])) begin
        $display("TEST_RESULT: FAIL: %s request[%0d] addr=%08h/%08h we=%0b/%0b size=%0d/%0d srt=%0b/%0b",
                 label, i, actual_addr[i], expected_addr[i],
                 actual_we[i], expected_we[i], actual_size[i],
                 expected_size[i], actual_srt[i], expected_srt[i]);
        failures++;
      end
    end
  endtask

  task automatic run_case(
      input int unsigned kind,
      input logic hrev_in,
      input logic vrev_in,
      input int unsigned psize,
      input int unsigned sptch,
      input int unsigned dptch,
      input int unsigned dx,
      input int unsigned dy,
      input int unsigned wx0,
      input int unsigned wy0,
      input int unsigned wx1,
      input int unsigned wy1,
      input logic srt,
      input logic rmw,
      input string label
  );
    int unsigned ax0;
    int unsigned ay0;
    int unsigned ax1;
    int unsigned ay1;
    int unsigned cx0;
    int unsigned cy0;
    int unsigned cx1;
    int unsigned cy1;
    int unsigned cdx;
    int unsigned cdy;
    int unsigned original_row;
    int unsigned original_col;
    int unsigned source_step;
    logic hit;
    logic changed;
    logic hrev;
    logic vrev;
    logic [DATA_WIDTH-1:0] source_raw;
    logic [DATA_WIDTH-1:0] source_top;
    logic [DATA_WIDTH-1:0] dest_raw;
    logic [DATA_WIDTH-1:0] dest_top;
    logic [DATA_WIDTH-1:0] source_addr;
    logic [DATA_WIDTH-1:0] dest_addr;
    logic [DATA_WIDTH-1:0] source_value;
    logic [DATA_WIDTH-1:0] expected_pixel;
    logic [DATA_WIDTH-1:0] actual_pixel;
    logic [DATA_WIDTH-1:0] expected_st;
    logic [DATA_WIDTH-1:0] expected_saddr;
    logic [DATA_WIDTH-1:0] expected_daddr;
    logic [DATA_WIDTH-1:0] mask;
    logic [DATA_WIDTH-1:0] initial_dest;

    hrev = hrev_in && (kind != KIND_FILL) && (kind != KIND_BXY);
    vrev = vrev_in && (kind != KIND_FILL) && (kind != KIND_BXY);
    source_step = (kind == KIND_BXY) ? 1 : psize;
    source_raw = (kind == KIND_XYXY) ? {SRC_Y, SRC_X} : LINEAR_SRC;
    source_top = (kind == KIND_XYXY)
               ? OFFSET_VAL + DATA_WIDTH'(SRC_Y * sptch + SRC_X * psize)
               : LINEAR_SRC;
    dest_raw = {DST_Y, DST_X};
    dest_top = OFFSET_VAL + DATA_WIDTH'(DST_Y * dptch + DST_X * psize);
    mask = field_mask(psize);
    initial_dest = rmw ? (32'h0000_0055 & mask) : 32'd0;

    ax0 = int'(DST_X);
    ay0 = int'(DST_Y);
    ax1 = int'(DST_X) + dx - 1;
    ay1 = int'(DST_Y) + dy - 1;
    hit = (wx0 <= wx1) && (wy0 <= wy1)
       && !((ax1 < wx0) || (ax0 > wx1) || (ay1 < wy0) || (ay0 > wy1));
    cx0 = (ax0 > wx0) ? ax0 : wx0;
    cy0 = (ay0 > wy0) ? ay0 : wy0;
    cx1 = (ax1 < wx1) ? ax1 : wx1;
    cy1 = (ay1 < wy1) ? ay1 : wy1;
    cdx = hit ? cx1 - cx0 + 1 : 0;
    cdy = hit ? cy1 - cy0 + 1 : 0;
    changed = !hit || (cx0 != ax0) || (cy0 != ay0)
                   || (cx1 != ax1) || (cy1 != ay1);

    begin_case();
    build_program(kind, psize, hrev_in, vrev_in, srt, rmw, sptch, dptch,
                  dx, dy, wx0, wy0, wx1, wy1);

    for (int unsigned row = 0; row < dy; row++) begin
      for (int unsigned col = 0; col < dx; col++) begin
        dest_addr = dest_top + DATA_WIDTH'(row * dptch + col * psize);
        write_field(dest_addr, psize, initial_dest);
        if (kind != KIND_FILL) begin
          source_addr = source_top
                      + DATA_WIDTH'(row * sptch + col * source_step);
          source_value = (kind == KIND_BXY)
                       ? DATA_WIDTH'((row * dx + col) & 1)
                       : DATA_WIDTH'(1 + row * dx + col);
          write_field(source_addr, source_step, source_value);
        end
      end
    end

    if (hit) begin
      for (int unsigned row = 0; row < cdy; row++) begin
        original_row = cy0 - ay0 + (vrev ? cdy - 1 - row : row);
        for (int unsigned col = 0; col < cdx; col++) begin
          original_col = cx0 - ax0 + (hrev ? cdx - 1 - col : col);
          dest_addr = dest_top
                    + DATA_WIDTH'(original_row * dptch
                                  + original_col * psize);
          if (kind == KIND_FILL) begin
            if (rmw) append_request(dest_addr, 1'b0, psize, srt);
            append_request(dest_addr, 1'b1, psize, srt);
          end else begin
            source_addr = source_top
                        + DATA_WIDTH'(original_row * sptch
                                    + original_col * source_step);
            append_request(source_addr, 1'b0, source_step, srt);
            if (rmw) append_request(dest_addr, 1'b0, psize, srt);
            append_request(dest_addr, 1'b1, psize, srt);
          end
        end
      end
    end

    launch_and_wait(label);
    compare_requests(label);

    for (int unsigned row = 0; row < dy; row++) begin
      for (int unsigned col = 0; col < dx; col++) begin
        dest_addr = dest_top + DATA_WIDTH'(row * dptch + col * psize);
        if ((int'(DST_X) + col >= cx0) && (int'(DST_X) + col <= cx1)
            && (int'(DST_Y) + row >= cy0)
            && (int'(DST_Y) + row <= cy1) && hit) begin
          if (kind == KIND_FILL) begin
            expected_pixel = 32'h0000_00AE & mask;
          end else if (kind == KIND_BXY) begin
            expected_pixel = (((row * dx + col) & 1) != 0)
                           ? (32'h0000_00AE & mask)
                           : (32'h0000_0003 & mask);
          end else begin
            expected_pixel = DATA_WIDTH'(1 + row * dx + col) & mask;
          end
          if (rmw) begin
            expected_pixel = (expected_pixel ^ initial_dest) & mask;
            expected_pixel[0] = initial_dest[0];
          end
        end else begin
          expected_pixel = initial_dest;
        end
        actual_pixel = read_field(dest_addr, psize);
        if (actual_pixel !== expected_pixel) begin
          $display("TEST_RESULT: FAIL: %s pixel[%0d,%0d] expected=%08h actual=%08h",
                   label, row, col, expected_pixel, actual_pixel);
          failures++;
        end
      end
    end

    expected_st = ST_SEED;
    expected_st[ST_V_BIT] = changed;
    if (kind == KIND_FILL) begin
      expected_saddr = source_raw;
      expected_daddr = hit
                     ? dest_top + DATA_WIDTH'((dy - 1) * dptch + dx * psize)
                     : dest_raw;
    end else begin
      expected_saddr = hit ? source_top + DATA_WIDTH'(dy * sptch) : source_raw;
      expected_daddr = hit ? dest_top + DATA_WIDTH'(dy * dptch) : dest_raw;
    end

    if (u_core.u_regfile.b_regs[B_SADDR_IDX] !== expected_saddr
        || u_core.u_regfile.b_regs[B_DADDR_IDX] !== expected_daddr
        || u_core.u_regfile.b_regs[B_DYDX_IDX] !== {16'(dy), 16'(dx)}) begin
      $display("TEST_RESULT: FAIL: %s context S=%08h/%08h D=%08h/%08h DYDX=%08h/%08h",
               label, u_core.u_regfile.b_regs[B_SADDR_IDX], expected_saddr,
               u_core.u_regfile.b_regs[B_DADDR_IDX], expected_daddr,
               u_core.u_regfile.b_regs[B_DYDX_IDX], {16'(dy), 16'(dx)});
      failures++;
    end
    if (u_core.u_regfile.a_regs[13] !== expected_st) begin
      $display("TEST_RESULT: FAIL: %s ST expected=%08h actual=%08h",
               label, expected_st, u_core.u_regfile.a_regs[13]);
      failures++;
    end
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND][INT_WV_BIT] !== 1'b0) begin
      $display("TEST_RESULT: FAIL: %s unexpectedly set WVP", label);
      failures++;
    end
    if (protocol_error
        || ((expected_count != 0) && !saw_graphics_wait)
        || (illegal_w !== 1'b0)) begin
      $display("TEST_RESULT: FAIL: %s common protocol=%0b wait=%0b illegal=%0b",
               label, protocol_error, saw_graphics_wait, illegal_w);
      failures++;
    end
  endtask

  initial begin : main
    failures = 0;

    // FILL: every individual edge, containment, exclusion, and all PSIZEs.
    run_case(KIND_FILL, 1, 1, 1, 128, 256, 5, 4,
             18, 18, 28, 28, 0, 0, "FILL contained PB ignored PSIZE1");
    run_case(KIND_FILL, 0, 0, 2, 128, 256, 5, 4,
             21, 18, 28, 28, 0, 0, "FILL left clip PSIZE2");
    run_case(KIND_FILL, 0, 0, 4, 128, 256, 5, 4,
             18, 18, 23, 28, 0, 0, "FILL right clip PSIZE4");
    run_case(KIND_FILL, 0, 0, 8, 128, 512, 5, 4,
             18, 21, 28, 28, 1, 1, "FILL top clip PSIZE8 SRT RMW");
    run_case(KIND_FILL, 0, 0, 16, 128, 512, 5, 4,
             18, 18, 28, 22, 0, 0, "FILL bottom clip PSIZE16");
    run_case(KIND_FILL, 0, 0, 8, 128, 256, 5, 4,
             30, 30, 32, 32, 1, 1, "FILL full exclusion RMW");
    run_case(KIND_FILL, 0, 0, 4, 128, 256, 5, 4,
             24, 18, 23, 28, 0, 1, "FILL empty-X window RMW");

    // Binary source: corner clips, one-pixel result, exclusion, and PB isolation.
    run_case(KIND_BXY, 1, 1, 4, 128, 256, 5, 4,
             21, 21, 28, 28, 0, 0, "B,XY top-left PB ignored");
    run_case(KIND_BXY, 0, 0, 8, 256, 512, 5, 4,
             18, 21, 23, 28, 1, 0, "B,XY top-right SRT");
    run_case(KIND_BXY, 1, 0, 16, 128, 512, 5, 4,
             24, 23, 24, 23, 0, 0, "B,XY one-pixel remainder");
    run_case(KIND_BXY, 0, 1, 2, 128, 256, 5, 4,
             30, 30, 32, 32, 0, 1, "B,XY full exclusion RMW");

    // L,XY: every direction, with a different corner removed in each case.
    run_case(KIND_LXY, 0, 0, 1, 128, 256, 5, 4,
             21, 21, 28, 28, 0, 0, "L,XY PB00 top-left");
    run_case(KIND_LXY, 1, 0, 2, 256, 512, 5, 4,
             18, 21, 23, 28, 0, 0, "L,XY PB10 top-right");
    run_case(KIND_LXY, 0, 1, 4, 128, 256, 5, 4,
             21, 18, 28, 22, 1, 1, "L,XY PB01 bottom-left SRT RMW");
    run_case(KIND_LXY, 1, 1, 8, 256, 512, 5, 4,
             18, 18, 23, 22, 0, 0, "L,XY PB11 bottom-right");
    run_case(KIND_LXY, 1, 1, 16, 256, 512, 5, 4,
             30, 30, 32, 32, 0, 0, "L,XY full exclusion");

    // XY,XY: all directions, independent conversions, containment/exclusion.
    run_case(KIND_XYXY, 0, 0, 16, 128, 512, 5, 4,
             21, 21, 28, 28, 0, 0, "XY,XY PB00 top-left");
    run_case(KIND_XYXY, 1, 0, 8, 256, 512, 5, 4,
             18, 21, 23, 28, 1, 0, "XY,XY PB10 top-right SRT");
    run_case(KIND_XYXY, 0, 1, 4, 128, 256, 5, 4,
             21, 18, 28, 22, 0, 0, "XY,XY PB01 bottom-left");
    run_case(KIND_XYXY, 1, 1, 2, 256, 512, 5, 4,
             18, 18, 23, 22, 0, 0, "XY,XY PB11 bottom-right");
    run_case(KIND_XYXY, 1, 1, 1, 128, 256, 5, 4,
             18, 18, 28, 28, 0, 0, "XY,XY contained reverse");
    run_case(KIND_XYXY, 0, 0, 8, 256, 512, 5, 4,
             30, 30, 32, 32, 1, 1, "XY,XY full exclusion SRT RMW");
    run_case(KIND_XYXY, 1, 1, 4, 128, 256, 5, 4,
             18, 23, 28, 22, 1, 1, "XY,XY empty-Y window SRT RMW");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (true W=3 FILL/PIXBLT preclipping)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #120_000_000;
    $display("TEST_RESULT: FAIL: tb_window_preclip hard timeout");
    $fatal(1);
  end

endmodule : tb_window_preclip
