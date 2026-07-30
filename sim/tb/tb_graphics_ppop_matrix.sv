// -----------------------------------------------------------------------------
// tb_graphics_ppop_matrix.sv
//
// Task 0169: generated graphics pixel-processing conformance matrix.
//
// Executes the 16 Boolean CONTROL.PPOP values at PSIZE 1/2/4/8/16 and the
// six arithmetic values at their defined PSIZE 4/8/16 through every graphics
// destination backend to which PPOP applies:
// PIXT register-to-linear/XY and memory-to-memory linear/XY, DRAV, LINE,
// FILL L/XY, full-color PIXBLT L,L/XY,XY, and binary PIXBLT B,L/B,XY.
// Deterministic word-positioned PMASK and transparency variants are crossed
// into the sweep. Binary cases transfer four LSB-first source bits to
// distinguish COLOR0/COLOR1 order. Every case uses sub-word pixel placements
// and three physical-word wait cycles. Task 0171 enables DPYCTL.SRT in every
// case and proves every pixel request—and no nonpixel request—carries it.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_graphics_ppop_matrix;
  import tms34010_pkg::*;

  localparam int unsigned MEM_WORDS = 2048;
  localparam int unsigned KIND_PIXT_L  = 0;
  localparam int unsigned KIND_PIXT_XY = 1;
  localparam int unsigned KIND_DRAV    = 2;
  localparam int unsigned KIND_LINE    = 3;
  localparam int unsigned KIND_FILL_L  = 4;
  localparam int unsigned KIND_FILL_XY = 5;
  localparam int unsigned KIND_PBLT_LL = 6;
  localparam int unsigned KIND_PBLT_XY = 7;
  localparam int unsigned KIND_PBLT_BL = 8;
  localparam int unsigned KIND_PBLT_BX = 9;
  localparam int unsigned KIND_PIXT_MM_L  = 10;
  localparam int unsigned KIND_PIXT_MM_XY = 11;
  localparam int unsigned KIND_COUNT      = 12;

  localparam logic [DATA_WIDTH-1:0] OFFSET = 32'h0000_4000;
  localparam logic [DATA_WIDTH-1:0] LINEAR_SRC = 32'h0000_5000;
  localparam logic [DATA_WIDTH-1:0] LINEAR_DST = 32'h0000_6000;
  localparam logic [DATA_WIDTH-1:0] BINARY_SRC = 32'h0000_5800;
  localparam logic [DATA_WIDTH-1:0] SRC_XY = {16'd1, 16'd1};
  localparam logic [DATA_WIDTH-1:0] DST_XY = {16'd2, 16'd3};
  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hE000_0010;

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
  localparam logic [DATA_WIDTH-1:0] A_PMASK =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PMASK) << 4);

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
    .host_mem_ack_i(1'b0), .host_mem_is_io_o(), .host_mem_io_rdata_o(),
    .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(),
    .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(),
    .video_hblank_o(), .video_vblank_o(), .video_blank_o(),
    .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(), .screen_refresh_org_o()
  );

  sim_memory_model #(
    .DEPTH_WORDS(MEM_WORDS),
    .WORD_WAIT_CYCLES(3)
  ) u_mem (
    .clk(clk), .rst(rst), .mem_req(mem_req), .mem_we(mem_we),
    .mem_addr(mem_addr), .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t index);
    movi_il_enc = 16'h09E0 | instr_word_t'(index);
  endfunction

  function automatic instr_word_t movi_il_b_enc(input reg_idx_t index);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(index);
  endfunction

  function automatic instr_word_t pixt_l_enc(
      input reg_idx_t source,
      input reg_idx_t destination
  );
    pixt_l_enc = 16'hF800 | (instr_word_t'(source) << 5)
               | instr_word_t'(destination);
  endfunction

  function automatic instr_word_t pixt_xy_enc(
      input reg_idx_t source,
      input reg_idx_t destination
  );
    pixt_xy_enc = 16'hF000 | (instr_word_t'(source) << 5)
                | instr_word_t'(destination);
  endfunction

  function automatic instr_word_t pixt_mm_l_enc(
      input reg_idx_t source,
      input reg_idx_t destination
  );
    pixt_mm_l_enc = 16'hFC00 | (instr_word_t'(source) << 5)
                  | instr_word_t'(destination);
  endfunction

  function automatic instr_word_t pixt_mm_xy_enc(
      input reg_idx_t source,
      input reg_idx_t destination
  );
    pixt_mm_xy_enc = 16'hF400 | (instr_word_t'(source) << 5)
                   | instr_word_t'(destination);
  endfunction

  function automatic instr_word_t pixt_load_l_enc(
      input reg_idx_t source,
      input reg_idx_t destination
  );
    pixt_load_l_enc = 16'hFA00 | (instr_word_t'(source) << 5)
                    | instr_word_t'(destination);
  endfunction

  function automatic instr_word_t pixt_load_xy_enc(
      input reg_idx_t source,
      input reg_idx_t destination
  );
    pixt_load_xy_enc = 16'hF200 | (instr_word_t'(source) << 5)
                     | instr_word_t'(destination);
  endfunction

  function automatic instr_word_t drav_enc(
      input reg_idx_t source,
      input reg_idx_t destination
  );
    drav_enc = 16'hF600 | (instr_word_t'(source) << 5)
             | instr_word_t'(destination);
  endfunction

  function automatic int unsigned place_word(
      input int unsigned p,
      input instr_word_t word_value
  );
    u_mem.mem[p] = word_value;
    place_word = p + 1;
  endfunction

  function automatic int unsigned place_movi_il(
      input int unsigned p,
      input reg_idx_t index,
      input logic [DATA_WIDTH-1:0] immediate
  );
    u_mem.mem[p] = movi_il_enc(index);
    u_mem.mem[p + 1] = immediate[15:0];
    u_mem.mem[p + 2] = immediate[31:16];
    place_movi_il = p + 3;
  endfunction

  function automatic int unsigned place_movi_il_b(
      input int unsigned p,
      input reg_idx_t index,
      input logic [DATA_WIDTH-1:0] immediate
  );
    u_mem.mem[p] = movi_il_b_enc(index);
    u_mem.mem[p + 1] = immediate[15:0];
    u_mem.mem[p + 2] = immediate[31:16];
    place_movi_il_b = p + 3;
  endfunction

  function automatic int unsigned place_store_abs(
      input int unsigned p,
      input reg_idx_t source,
      input logic [DATA_WIDTH-1:0] address
  );
    u_mem.mem[p] = 16'h0580 | instr_word_t'(source);
    u_mem.mem[p + 1] = address[15:0];
    u_mem.mem[p + 2] = address[31:16];
    place_store_abs = p + 3;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] pixel_mask(
      input int unsigned psize
  );
    pixel_mask = (32'd1 << psize) - 32'd1;
  endfunction

  function automatic int unsigned psize_from_index(input int unsigned index);
    unique case (index)
      0: psize_from_index = 1;
      1: psize_from_index = 2;
      2: psize_from_index = 4;
      3: psize_from_index = 8;
      default: psize_from_index = 16;
    endcase
  endfunction

  function automatic logic [DATA_WIDTH-1:0] ppop_reference(
      input logic [DATA_WIDTH-1:0] source,
      input logic [DATA_WIDTH-1:0] destination,
      input logic [4:0] ppop,
      input logic [DATA_WIDTH-1:0] mask
  );
    logic [DATA_WIDTH-1:0] source_pixel;
    logic [DATA_WIDTH-1:0] destination_pixel;
    logic [DATA_WIDTH-1:0] sum;
    source_pixel = source & mask;
    destination_pixel = destination & mask;
    sum = source_pixel + destination_pixel;
    unique case (ppop)
      5'h00: ppop_reference = source_pixel;
      5'h01: ppop_reference = source_pixel & destination_pixel;
      5'h02: ppop_reference = source_pixel & ~destination_pixel;
      5'h03: ppop_reference = '0;
      5'h04: ppop_reference = source_pixel | ~destination_pixel;
      5'h05: ppop_reference = ~(source_pixel ^ destination_pixel);
      5'h06: ppop_reference = ~destination_pixel;
      5'h07: ppop_reference = ~(source_pixel | destination_pixel);
      5'h08: ppop_reference = source_pixel | destination_pixel;
      5'h09: ppop_reference = destination_pixel;
      5'h0A: ppop_reference = source_pixel ^ destination_pixel;
      5'h0B: ppop_reference = ~source_pixel & destination_pixel;
      5'h0C: ppop_reference = mask;
      5'h0D: ppop_reference = ~source_pixel | destination_pixel;
      5'h0E: ppop_reference = ~(source_pixel & destination_pixel);
      5'h0F: ppop_reference = ~source_pixel;
      5'h10: ppop_reference = sum;
      5'h11: ppop_reference = (sum > mask) ? mask : sum;
      5'h12: ppop_reference = destination_pixel - source_pixel;
      5'h13: ppop_reference =
          (destination_pixel >= source_pixel)
            ? destination_pixel - source_pixel : 32'd0;
      5'h14: ppop_reference =
          (destination_pixel >= source_pixel)
            ? destination_pixel : source_pixel;
      default: ppop_reference =
          (destination_pixel <= source_pixel)
            ? destination_pixel : source_pixel; // 0x15 MIN
    endcase
    ppop_reference &= mask;
  endfunction

  function automatic logic [DATA_WIDTH-1:0] merged_reference(
      input logic [DATA_WIDTH-1:0] source,
      input logic [DATA_WIDTH-1:0] destination,
      input logic [4:0] ppop,
      input logic [DATA_WIDTH-1:0] mask,
      input logic [DATA_WIDTH-1:0] source_pmask,
      input logic [DATA_WIDTH-1:0] destination_pmask,
      input logic transparent
  );
    logic [DATA_WIDTH-1:0] processed;
    logic [DATA_WIDTH-1:0] masked_result;
    processed = ppop_reference(source & ~source_pmask,
                               destination & ~destination_pmask,
                               ppop, mask);
    masked_result = processed & ~destination_pmask & mask;
    if (transparent && (masked_result == 0))
      merged_reference = destination & mask;
    else
      merged_reference =
          (masked_result
           | (destination & destination_pmask)) & mask;
  endfunction

  task automatic write_field(
      input logic [DATA_WIDTH-1:0] bit_address,
      input int unsigned size,
      input logic [DATA_WIDTH-1:0] value
  );
    for (int unsigned bit_index = 0; bit_index < size; bit_index++)
      u_mem.mem[(bit_address + bit_index) >> 4]
               [(bit_address + bit_index) & 15] = value[bit_index];
  endtask

  function automatic logic [DATA_WIDTH-1:0] read_field(
      input logic [DATA_WIDTH-1:0] bit_address,
      input int unsigned size
  );
    logic [DATA_WIDTH-1:0] value;
    value = '0;
    for (int unsigned bit_index = 0; bit_index < size; bit_index++)
      value[bit_index] =
          u_mem.mem[(bit_address + bit_index) >> 4]
                   [(bit_address + bit_index) & 15];
    read_field = value;
  endfunction

  int unsigned failures;
  logic protocol_error;
  logic srt_classification_error;
  logic saw_graphics_wait;
  logic pixel_request_state;
  int unsigned pixel_srt_acks;
  logic saw_mask_induced_transparency;
  logic held_req_q;
  logic held_we_q;
  logic [ADDR_WIDTH-1:0] held_addr_q;
  logic [FIELD_SIZE_WIDTH-1:0] held_size_q;
  logic [DATA_WIDTH-1:0] held_wdata_q;
  logic held_srt_q;

  function automatic logic graphics_state(input core_state_t state);
    graphics_state = (state == CORE_MEMORY) || (state == CORE_DRAV)
                  || (state == CORE_LINE_DRAW) || (state == CORE_FILL)
                  || (state == CORE_PBLT);
  endfunction

  always_comb begin
    pixel_request_state =
        (state_w == CORE_DRAV)
        || (state_w == CORE_LINE_DRAW)
        || (state_w == CORE_FILL)
        || (state_w == CORE_PBLT)
        || ((state_w == CORE_MEMORY) && u_core.decoded.force_pixel);
  end

  always @(posedge clk) begin
    if (rst) begin
      protocol_error <= 1'b0;
      srt_classification_error <= 1'b0;
      saw_graphics_wait <= 1'b0;
      pixel_srt_acks <= 0;
      held_req_q <= 1'b0;
      held_we_q <= 1'b0;
      held_addr_q <= '0;
      held_size_q <= '0;
      held_wdata_q <= '0;
      held_srt_q <= 1'b0;
    end else begin
      if (mem_req && (mem_srt !== pixel_request_state))
        srt_classification_error <= 1'b1;
      if (mem_req && mem_ack && pixel_request_state)
        pixel_srt_acks <= pixel_srt_acks + 1;
      if (graphics_state(state_w) && mem_req && !mem_ack)
        saw_graphics_wait <= 1'b1;
      if (held_req_q
          && (!mem_req || mem_we !== held_we_q || mem_addr !== held_addr_q
              || mem_size !== held_size_q || mem_wdata !== held_wdata_q
              || mem_srt !== held_srt_q))
        protocol_error <= 1'b1;
      if (mem_req && !mem_ack && !held_req_q) begin
        held_req_q <= 1'b1;
        held_we_q <= mem_we;
        held_addr_q <= mem_addr;
        held_size_q <= mem_size;
        held_wdata_q <= mem_wdata;
        held_srt_q <= mem_srt;
      end
      if (mem_ack) held_req_q <= 1'b0;
    end
  end

  task automatic begin_case;
    @(negedge clk);
    rst = 1'b1;
    repeat (3) @(posedge clk);
    #1;
    for (int unsigned index = 0; index < 128; index++)
      u_mem.mem[index] = 16'h0300;
    for (int unsigned index = 1024; index < MEM_WORDS; index++)
      u_mem.mem[index] = 16'h0000;
  endtask

  task automatic run_case(
      input int unsigned kind,
      input int unsigned psize,
      input logic [4:0] ppop
  );
    int unsigned p;
    int unsigned pixel_count;
    logic transparent;
    logic [DATA_WIDTH-1:0] mask;
    logic [DATA_WIDTH-1:0] pmask;
    logic [DATA_WIDTH-1:0] source0;
    logic [DATA_WIDTH-1:0] source1;
    logic [DATA_WIDTH-1:0] destination;
    logic [DATA_WIDTH-1:0] source_address;
    logic [DATA_WIDTH-1:0] destination_address;
    logic [DATA_WIDTH-1:0] source_xy_address;
    logic [DATA_WIDTH-1:0] destination_xy_address;
    logic [DATA_WIDTH-1:0] raw_source;
    logic [DATA_WIDTH-1:0] raw_destination;
    logic [DATA_WIDTH-1:0] expected;
    logic [DATA_WIDTH-1:0] actual;
    logic [DATA_WIDTH-1:0] control;
    logic binary;
    logic reached_halt;

    mask = pixel_mask(psize);
    transparent = ((int'(ppop) + kind + psize) % 3) == 0;
    pmask = (32'h0000_A55A ^ DATA_WIDTH'(kind * 16'h1111)
            ^ DATA_WIDTH'(int'(ppop) * 16'h0101)) & 32'h0000_FFFF;
    source0 = 32'h0000_A5A5 & mask;
    source1 = ~source0 & mask;
    destination = 32'h0000_5A3C & mask;
    source_address = LINEAR_SRC
                   + DATA_WIDTH'(((int'(ppop) + 1) * psize) & 15);
    destination_address = LINEAR_DST
                        + DATA_WIDTH'(((int'(ppop) + kind) * psize) & 15);
    source_xy_address = OFFSET + 32'd256 + DATA_WIDTH'(psize);
    destination_xy_address = OFFSET + 32'd512 + DATA_WIDTH'(3 * psize);
    binary = (kind == KIND_PBLT_BL) || (kind == KIND_PBLT_BX);
    pixel_count = binary ? 4 : 1;
    control = (DATA_WIDTH'(ppop) << CTRL_PPOP_LO)
            | (transparent ? (DATA_WIDTH'(1) << CTRL_T_BIT) : 32'd0);

    begin_case();

    p = 0;
    p = place_word(p, 16'h0550); // SETF FS0=16
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(psize));
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(
        p, 4'd0, DATA_WIDTH'(1) << DPYCTL_SRT_BIT);
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_movi_il(p, 4'd0, 32'd23); // 256-bit pitch
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il(p, 4'd0, control);
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_movi_il(p, 4'd0, pmask);
    p = place_store_abs(p, 4'd0, A_PMASK);

    raw_source = (kind == KIND_PBLT_XY) ? SRC_XY
               : binary ? BINARY_SRC : source_address;
    raw_destination = ((kind == KIND_PIXT_XY) || (kind == KIND_DRAV)
                       || (kind == KIND_LINE) || (kind == KIND_FILL_XY)
                       || (kind == KIND_PBLT_XY) || (kind == KIND_PBLT_BX)
                       || (kind == KIND_PIXT_MM_XY))
                    ? DST_XY : destination_address;
    p = place_movi_il_b(p, 4'd0, raw_source);
    p = place_movi_il_b(p, 4'd1, 32'd256);
    p = place_movi_il_b(p, 4'd2, raw_destination);
    p = place_movi_il_b(p, 4'd3, 32'd256);
    p = place_movi_il_b(p, 4'd4, OFFSET);
    p = place_movi_il_b(p, 4'd5, {16'd0, 16'd0});
    p = place_movi_il_b(p, 4'd6, {16'd20, 16'd20});
    p = place_movi_il_b(p, 4'd7, {16'd1, 16'(pixel_count)});
    p = place_movi_il_b(p, 4'd8, source0);
    p = place_movi_il_b(p, 4'd9, binary ? source1 : source0);
    p = place_movi_il_b(p, 4'd10, 32'd1);
    p = place_movi_il_b(p, 4'd11, 32'h0000_0001);
    p = place_movi_il_b(p, 4'd12, 32'h0000_0001);
    p = place_movi_il(
        p, 4'd1,
        (kind == KIND_PIXT_MM_L) ? source_address
          : (kind == KIND_PIXT_MM_XY) ? SRC_XY : source0);
    p = place_movi_il(p, 4'd2,
                      (kind == KIND_PIXT_XY || kind == KIND_DRAV
                       || kind == KIND_PIXT_MM_XY)
                        ? DST_XY : destination_address);
    p = place_movi_il(p, 4'd14, 32'd1); // normalize NCZV

    unique case (kind)
      KIND_PIXT_L:  p = place_word(p, pixt_l_enc(4'd1, 4'd2));
      KIND_PIXT_XY: p = place_word(p, pixt_xy_enc(4'd1, 4'd2));
      KIND_DRAV:    p = place_word(p, drav_enc(4'd1, 4'd2));
      KIND_LINE:    p = place_word(p, 16'hDF1A);
      KIND_FILL_L:  p = place_word(p, 16'h0FC0);
      KIND_FILL_XY: p = place_word(p, 16'h0FE0);
      KIND_PBLT_LL: p = place_word(p, 16'h0F00);
      KIND_PBLT_XY: p = place_word(p, 16'h0F60);
      KIND_PBLT_BL: p = place_word(p, 16'h0F80);
      KIND_PBLT_BX: p = place_word(p, 16'h0FA0);
      KIND_PIXT_MM_L:
        p = place_word(p, pixt_mm_l_enc(4'd1, 4'd2));
      default:
        p = place_word(p, pixt_mm_xy_enc(4'd1, 4'd2));
    endcase
    p = place_word(p, 16'hC0FF);

    if ((kind == KIND_PBLT_LL) || (kind == KIND_PBLT_XY)
        || (kind == KIND_PIXT_MM_L) || (kind == KIND_PIXT_MM_XY))
      write_field(((kind == KIND_PBLT_XY)
                   || (kind == KIND_PIXT_MM_XY))
                    ? source_xy_address : source_address,
                  psize, source0);
    if (binary)
      write_field(BINARY_SRC, 4, 32'b1101);

    for (int unsigned pixel = 0; pixel < pixel_count; pixel++) begin
      logic [DATA_WIDTH-1:0] pixel_address;
      pixel_address = ((kind == KIND_PIXT_XY) || (kind == KIND_DRAV)
                       || (kind == KIND_LINE) || (kind == KIND_FILL_XY)
                       || (kind == KIND_PBLT_XY) || (kind == KIND_PBLT_BX)
                       || (kind == KIND_PIXT_MM_XY))
                    ? destination_xy_address + DATA_WIDTH'(pixel * psize)
                    : destination_address + DATA_WIDTH'(pixel * psize);
      write_field(pixel_address, psize, destination);
    end

    @(negedge clk);
    rst = 1'b0;
    reached_halt = 1'b0;
    begin : wait_for_halt
      for (int unsigned cycle = 0; cycle < 12000; cycle++) begin
        @(posedge clk);
        #1;
        if ((state_w == CORE_EXECUTE) && (instr_w == 16'hC0FF)) begin
          reached_halt = 1'b1;
          disable wait_for_halt;
        end
      end
    end

    if (!reached_halt) begin
      $display("TEST_RESULT: FAIL: matrix timeout kind=%0d psize=%0d ppop=%02h",
               kind, psize, ppop);
      failures++;
    end
    for (int unsigned pixel = 0; pixel < pixel_count; pixel++) begin
      logic [DATA_WIDTH-1:0] pixel_source;
      logic [DATA_WIDTH-1:0] pixel_address;
      logic [DATA_WIDTH-1:0] pixel_source_address;
      logic [DATA_WIDTH-1:0] source_pmask;
      logic [DATA_WIDTH-1:0] destination_pmask;
      logic [DATA_WIDTH-1:0] unmasked_result;
      pixel_address = ((kind == KIND_PIXT_XY) || (kind == KIND_DRAV)
                       || (kind == KIND_LINE) || (kind == KIND_FILL_XY)
                       || (kind == KIND_PBLT_XY) || (kind == KIND_PBLT_BX)
                       || (kind == KIND_PIXT_MM_XY))
                    ? destination_xy_address + DATA_WIDTH'(pixel * psize)
                    : destination_address + DATA_WIDTH'(pixel * psize);
      pixel_source = binary
          ? ((((32'b1101 >> pixel) & 1) != 0) ? source1 : source0)
          : source0;
      if ((kind == KIND_DRAV) || (kind == KIND_LINE)
          || (kind == KIND_FILL_L) || (kind == KIND_FILL_XY) || binary)
        pixel_source = (pixel_source >> pixel_address[3:0]) & mask;
      pixel_source_address =
          ((kind == KIND_PBLT_XY) || (kind == KIND_PIXT_MM_XY))
            ? source_xy_address + DATA_WIDTH'(pixel * psize)
            : source_address + DATA_WIDTH'(pixel * psize);
      destination_pmask = (pmask >> pixel_address[3:0]) & mask;
      if ((kind == KIND_PBLT_LL) || (kind == KIND_PBLT_XY)
          || (kind == KIND_PIXT_MM_L) || (kind == KIND_PIXT_MM_XY))
        source_pmask = (pmask >> pixel_source_address[3:0]) & mask;
      else if (binary)
        source_pmask = destination_pmask;
      else
        source_pmask = '0;
      expected = merged_reference(
          pixel_source, destination, ppop, mask,
          source_pmask, destination_pmask, transparent);
      unmasked_result =
          ppop_reference(pixel_source & ~source_pmask,
                         destination & ~destination_pmask, ppop, mask);
      if (transparent && ((unmasked_result & mask) != 0)
          && ((unmasked_result & ~destination_pmask & mask) == 0))
        saw_mask_induced_transparency = 1'b1;
      actual = read_field(pixel_address, psize);
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: matrix kind=%0d psize=%0d ppop=%02h T=%0b PMASK=%04h pixel=%0d src=%08h dst=%08h expected=%08h actual=%08h",
                 kind, psize, ppop, transparent, pmask[15:0], pixel,
                 pixel_source, destination, expected, actual);
        failures++;
      end
    end
    if (u_core.u_status_reg.st_q[ST_N_BIT]
        || u_core.u_status_reg.st_q[ST_C_BIT]
        || u_core.u_status_reg.st_q[ST_Z_BIT]
        || u_core.u_status_reg.st_q[ST_V_BIT]
        || illegal_w || protocol_error || srt_classification_error
        || !saw_graphics_wait || (pixel_srt_acks == 0)) begin
      $display("TEST_RESULT: FAIL: matrix side effects kind=%0d psize=%0d ppop=%02h ST=%08h illegal=%0b protocol=%0b srt_error=%0b srt_acks=%0d wait=%0b",
               kind, psize, ppop, u_core.u_status_reg.st_q, illegal_w,
               protocol_error, srt_classification_error, pixel_srt_acks,
               saw_graphics_wait);
      failures++;
    end
  endtask

  task automatic run_load_case(
      input logic xy_source,
      input int unsigned psize
  );
    int unsigned p;
    logic [DATA_WIDTH-1:0] mask;
    logic [DATA_WIDTH-1:0] pmask;
    logic [DATA_WIDTH-1:0] source_address;
    logic [DATA_WIDTH-1:0] source_pointer;
    logic [DATA_WIDTH-1:0] source_value;
    logic [DATA_WIDTH-1:0] source_pmask;
    logic [DATA_WIDTH-1:0] expected;
    logic [DATA_WIDTH-1:0] expected_st;
    logic reached_halt;

    mask = pixel_mask(psize);
    pmask = (32'h0000_A55A
             ^ DATA_WIDTH'(psize * 16'h1111)
             ^ (xy_source ? 32'h0000_5AA5 : 32'd0)) & 32'h0000_FFFF;
    source_address = xy_source
                   ? OFFSET + 32'd256 + DATA_WIDTH'(psize)
                   : LINEAR_SRC + DATA_WIDTH'((3 * psize) & 15);
    source_pointer = xy_source ? SRC_XY : source_address;
    source_value = (32'h0000_D6B5 ^ DATA_WIDTH'(psize * 16'h0101)) & mask;
    source_pmask = (pmask >> source_address[3:0]) & mask;
    expected = source_value & ~source_pmask & mask;
    expected_st = ST_SEED;
    expected_st[ST_V_BIT] = (expected != 0);

    begin_case();
    p = 0;
    p = place_word(p, 16'h0550); // SETF FS0=16
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(psize));
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(
        p, 4'd0, DATA_WIDTH'(1) << DPYCTL_SRT_BIT);
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_movi_il(p, 4'd0, 32'd23); // 256-bit source pitch
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_movi_il(p, 4'd0, pmask);
    p = place_store_abs(p, 4'd0, A_PMASK);
    p = place_movi_il_b(p, 4'd4, OFFSET);
    p = place_movi_il(p, 4'd1, source_pointer);
    p = place_movi_il(p, 4'd14, ST_SEED);
    p = place_word(p, 16'h01AE); // PUTST A14
    p = place_word(
        p, xy_source ? pixt_load_xy_enc(4'd1, 4'd3)
                     : pixt_load_l_enc(4'd1, 4'd3));
    p = place_word(p, 16'hC0FF);
    write_field(source_address, psize, source_value);

    @(negedge clk);
    rst = 1'b0;
    reached_halt = 1'b0;
    begin : wait_for_load_halt
      for (int unsigned cycle = 0; cycle < 4000; cycle++) begin
        @(posedge clk);
        #1;
        if ((state_w == CORE_EXECUTE) && (instr_w == 16'hC0FF)) begin
          reached_halt = 1'b1;
          disable wait_for_load_halt;
        end
      end
    end

    if (!reached_halt) begin
      $display("TEST_RESULT: FAIL: PMASK read timeout XY=%0b psize=%0d",
               xy_source, psize);
      failures++;
    end
    if ((u_core.u_regfile.a_regs[3] !== expected)
        || (u_core.u_status_reg.st_q !== expected_st)
        || illegal_w || protocol_error || srt_classification_error
        || !saw_graphics_wait || (pixel_srt_acks == 0)) begin
      $display("TEST_RESULT: FAIL: PMASK read XY=%0b psize=%0d addr=%08h raw=%08h PMASK=%04h field=%08h result=%08h/%08h ST=%08h/%08h illegal=%0b protocol=%0b srt_error=%0b srt_acks=%0d wait=%0b",
               xy_source, psize, source_address, source_value, pmask[15:0],
               source_pmask, u_core.u_regfile.a_regs[3], expected,
               u_core.u_status_reg.st_q, expected_st, illegal_w,
               protocol_error, srt_classification_error, pixel_srt_acks,
               saw_graphics_wait);
      failures++;
    end
  endtask

  initial begin : main
    failures = 0;
    saw_mask_induced_transparency = 1'b0;
    for (int unsigned size_index = 0; size_index < 5; size_index++) begin
      for (int unsigned ppop = 0; ppop <= 16'h15; ppop++) begin
        // Production CONTROL pages define arithmetic PPOP only for 4-, 8-,
        // and 16-bit pixels. PSIZE 1/2 arithmetic behavior is intentionally
        // outside the conformance matrix rather than assigned invented rules.
        if ((ppop < 16'h10) || (psize_from_index(size_index) >= 4)) begin
          for (int unsigned kind = 0; kind < KIND_COUNT; kind++)
            run_case(kind, psize_from_index(size_index), ppop[4:0]);
        end
      end
    end
    for (int unsigned size_index = 0; size_index < 5; size_index++) begin
      run_load_case(1'b0, psize_from_index(size_index));
      run_load_case(1'b1, psize_from_index(size_index));
    end
    if (!saw_mask_induced_transparency) begin
      $display("TEST_RESULT: FAIL: matrix did not exercise PMASK-induced transparency");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (graphics matrix: 1176 PPOP + 10 PMASK-read cases)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed across %0d cases",
               failures, 1186);
    $finish;
  end

  initial begin : watchdog
    #600_000_000;
    $display("TEST_RESULT: FAIL: tb_graphics_ppop_matrix hard timeout");
    $fatal(1);
  end

endmodule : tb_graphics_ppop_matrix
