// -----------------------------------------------------------------------------
// tb_line_interrupt.sv
//
// Task 0168: end-to-end interrupt/RETI continuation for LINE.
//
// Every nonfinal pixel in horizontal, vertical, diagonal, shallow, steep, and
// all signed direction combinations is interrupted with either DI or NMIM=0
// NMI. The handler preserves B state and returns through RETI. A reference
// Bresenham model checks every B0/B2/B10 continuation image, exact field
// request order, framebuffer, final context/status, stack PC/ST/PBX, repeated
// entry, held-request stability, W=3 clipping, PPOP/PMASK RMW, SRT, and three
// inserted physical-word wait cycles.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_line_interrupt;
  import tms34010_pkg::*;

  localparam int unsigned MEM_WORDS = 8192;
  localparam int unsigned MAX_PIXELS = 16;
  localparam int unsigned MAX_REQUESTS = 64;
  localparam logic [DATA_WIDTH-1:0] OFFSET = 32'h0000_4000;
  localparam logic [DATA_WIDTH-1:0] SP_INIT = 32'h0000_1800;
  localparam int unsigned ISR_WORD = 256;
  localparam logic [DATA_WIDTH-1:0] ISR_PC =
      DATA_WIDTH'(ISR_WORD * INSTR_WORD_BITS);
  localparam int unsigned DI_VEC_WORD =
      (INT_VEC_DI >> LOCAL_WORD_ADDR_LSB) & (MEM_WORDS - 1);
  localparam int unsigned NMI_VEC_WORD =
      (INT_VEC_NMI >> LOCAL_WORD_ADDR_LSB) & (MEM_WORDS - 1);
  localparam logic [DATA_WIDTH-1:0] BASE_ST =
      ST_RESET_VALUE | (DATA_WIDTH'(1) << ST_IE_BIT);

  localparam logic [DATA_WIDTH-1:0] A_CONTROL =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONTROL) << 4);
  localparam logic [DATA_WIDTH-1:0] A_CONVDP =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_CONVDP) << 4);
  localparam logic [DATA_WIDTH-1:0] A_PSIZE =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PSIZE) << 4);
  localparam logic [DATA_WIDTH-1:0] A_PMASK =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_PMASK) << 4);
  localparam logic [DATA_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [DATA_WIDTH-1:0] A_INTENB =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_INTENB) << 4);
  localparam logic [DATA_WIDTH-1:0] A_INTPEND =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_INTPEND) << 4);

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
  logic                        dpyint_set;
  logic                        host_req;
  logic                        host_we;
  host_reg_sel_t               host_reg;
  logic [1:0]                  host_be;
  logic [15:0]                 host_wdata;
  logic                        host_ack;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1),
    .video_vsync_n_i(1'b1), .rst(rst), .vclk_rst_i(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_srt(mem_srt),
    .mem_iaq(), .mem_is_io(), .mem_io_we(), .mem_io_rdata(),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack), .state_o(state_w),
    .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w),
    .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1),
    .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(host_req),
    .host_we_i(host_we), .host_reg_i(host_reg), .host_be_i(host_be),
    .host_wdata_i(host_wdata), .host_rdata_o(), .host_ack_o(host_ack),
    .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(),
    .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i(1'b0), .host_mem_is_io_o(), .host_mem_io_rdata_o(),
    .dpyint_set_i(dpyint_set), .refresh_req_o(), .refresh_row_o(),
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

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction

  function automatic instr_word_t movi_il_b_enc(input reg_idx_t i);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(i);
  endfunction

  function automatic instr_word_t setf_enc(input logic [4:0] fs);
    setf_enc = 16'h0540 | instr_word_t'(fs);
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

  task automatic write_field(
      input logic [DATA_WIDTH-1:0] bit_address,
      input logic [7:0] value
  );
    for (int unsigned bit_index = 0; bit_index < 8; bit_index++)
      u_mem.mem[(bit_address + bit_index) >> 4]
               [(bit_address + bit_index) & 15] = value[bit_index];
  endtask

  function automatic logic [7:0] read_field(
      input logic [DATA_WIDTH-1:0] bit_address
  );
    logic [7:0] value;
    value = '0;
    for (int unsigned bit_index = 0; bit_index < 8; bit_index++)
      value[bit_index] =
          u_mem.mem[(bit_address + bit_index) >> 4]
                   [(bit_address + bit_index) & 15];
    read_field = value;
  endfunction

  logic [ADDR_WIDTH-1:0]       actual_addr [0:MAX_REQUESTS-1];
  logic                        actual_we   [0:MAX_REQUESTS-1];
  logic                        actual_srt  [0:MAX_REQUESTS-1];
  logic [ADDR_WIDTH-1:0]       expected_addr [0:MAX_REQUESTS-1];
  logic                        expected_we   [0:MAX_REQUESTS-1];
  logic                        expected_srt  [0:MAX_REQUESTS-1];
  logic [DATA_WIDTH-1:0]       expected_d [0:MAX_PIXELS-1];
  logic [DATA_WIDTH-1:0]       expected_daddr [0:MAX_PIXELS-1];
  logic [DATA_WIDTH-1:0]       expected_count [0:MAX_PIXELS-1];
  logic [DATA_WIDTH-1:0]       expected_pixel_addr [0:MAX_PIXELS-1];
  logic [7:0]                  expected_pixel_value [0:MAX_PIXELS-1];

  int unsigned failures;
  int unsigned actual_request_count;
  int unsigned expected_request_count;
  int unsigned checkpoint_count;
  int unsigned interrupt_count;
  int unsigned setup_count;
  logic protocol_error;
  logic saw_wait;
  logic held_req_q;
  logic held_we_q;
  logic [ADDR_WIDTH-1:0] held_addr_q;
  logic [FIELD_SIZE_WIDTH-1:0] held_size_q;
  logic [DATA_WIDTH-1:0] held_wdata_q;
  logic held_srt_q;
  logic inject_enable;
  logic inject_nmi;
  logic [DATA_WIDTH-1:0] line_opcode_pc;

  always @(posedge clk) begin
    if (rst) begin
      actual_request_count <= 0;
      interrupt_count <= 0;
      setup_count <= 0;
      protocol_error <= 1'b0;
      saw_wait <= 1'b0;
      held_req_q <= 1'b0;
      held_we_q <= 1'b0;
      held_addr_q <= '0;
      held_size_q <= '0;
      held_wdata_q <= '0;
      held_srt_q <= 1'b0;
    end else begin
      if ((state_w == CORE_LINE_DRAW) && mem_req && mem_ack) begin
        if (actual_request_count < MAX_REQUESTS) begin
          actual_addr[actual_request_count] <= mem_addr;
          actual_we[actual_request_count] <= mem_we;
          actual_srt[actual_request_count] <= mem_srt;
        end
        actual_request_count <= actual_request_count + 1;
      end
      if ((state_w == CORE_LINE_DRAW) && mem_req && !mem_ack)
        saw_wait <= 1'b1;
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

      if (state_w == CORE_LINE_SETUP1)
        setup_count <= setup_count + 1;
      if ((state_w == CORE_INT_PUSH_PC) && mem_ack) begin
        if (mem_addr !== (SP_INIT - WORD_BIT_SIZE)
            || mem_size !== MEM_SIZE_32 || mem_wdata !== line_opcode_pc) begin
          $display("TEST_RESULT: FAIL: LINE PC stack addr=%08h size=%0d data=%08h expected=%08h",
                   mem_addr, mem_size, mem_wdata, line_opcode_pc);
          failures++;
        end
      end
      if ((state_w == CORE_INT_PUSH_ST) && mem_ack) begin
        if (mem_addr !== (SP_INIT - WORD_BIT_SIZE_2)
            || mem_size !== MEM_SIZE_32 || mem_wdata !== BASE_ST
            || mem_wdata[ST_PBX_BIT] !== 1'b0) begin
          $display("TEST_RESULT: FAIL: LINE ST stack addr=%08h size=%0d data=%08h PBX=%0b",
                   mem_addr, mem_size, mem_wdata,
                   mem_wdata[ST_PBX_BIT]);
          failures++;
        end
        interrupt_count <= interrupt_count + 1;
      end
    end
  end

  // B10 commits on this edge; sample the complete continuation image after
  // nonblocking regfile writes.
  always @(posedge clk) begin
    if (rst) begin
      checkpoint_count = 0;
    end else if (state_w == CORE_LINE_CKPT_COUNT) begin
      #1;
      if (checkpoint_count >= MAX_PIXELS
          || u_core.u_regfile.b_regs[0] !== expected_d[checkpoint_count]
          || u_core.u_regfile.b_regs[2] !== expected_daddr[checkpoint_count]
          || u_core.u_regfile.b_regs[10] !== expected_count[checkpoint_count]) begin
        $display("TEST_RESULT: FAIL: LINE checkpoint[%0d] B0=%08h/%08h B2=%08h/%08h B10=%08h/%08h",
                 checkpoint_count, u_core.u_regfile.b_regs[0],
                 expected_d[checkpoint_count], u_core.u_regfile.b_regs[2],
                 expected_daddr[checkpoint_count],
                 u_core.u_regfile.b_regs[10],
                 expected_count[checkpoint_count]);
        failures++;
      end
      checkpoint_count = checkpoint_count + 1;
    end
  end

  // Request every legal checkpoint. Host NMI is issued early in the
  // three-state serialization chain; DI becomes sticky on the next edge.
  always @(negedge clk) begin
    if (rst) begin
      dpyint_set = 1'b0;
      host_req = 1'b0;
      host_we = 1'b0;
      host_reg = HOST_REG_HSTCTL;
      host_be = 2'b00;
      host_wdata = 16'd0;
    end else begin
      dpyint_set = 1'b0;
      if (host_req && host_ack) begin
        host_req = 1'b0;
        host_we = 1'b0;
        host_be = 2'b00;
      end
      if (inject_enable && (state_w == CORE_LINE_CKPT_D)) begin
        if (inject_nmi) begin
          host_req = 1'b1;
          host_we = 1'b1;
          host_reg = HOST_REG_HSTCTL;
          host_be = 2'b10;
          host_wdata = 16'(1 << HSTCTL_NMI_BIT);
        end else begin
          dpyint_set = 1'b1;
        end
      end
    end
  end

  task automatic begin_case;
    @(negedge clk);
    rst = 1'b1;
    repeat (3) @(posedge clk);
    #1;
    for (int unsigned index = 0; index < MEM_WORDS; index++)
      u_mem.mem[index] = 16'h0300;
    expected_request_count = 0;
    checkpoint_count = 0;
    inject_enable = 1'b0;
  endtask

  task automatic append_request(
      input logic [DATA_WIDTH-1:0] address,
      input logic write_access,
      input logic srt
  );
    expected_addr[expected_request_count] = address;
    expected_we[expected_request_count] = write_access;
    expected_srt[expected_request_count] = srt;
    expected_request_count++;
  endtask

  task automatic build_program(
      input logic [DATA_WIDTH-1:0] initial_d,
      input logic [DATA_WIDTH-1:0] initial_daddr,
      input logic [15:0] a,
      input logic [15:0] b,
      input logic [DATA_WIDTH-1:0] inc1,
      input logic [DATA_WIDTH-1:0] inc2,
      input int unsigned count,
      input logic w3,
      input logic rmw,
      input logic srt
  );
    int unsigned p;
    logic [DATA_WIDTH-1:0] control;
    control = (DATA_WIDTH'(w3 ? 3 : 0) << CTRL_W_LO)
            | (rmw ? (DATA_WIDTH'(5'h0A) << CTRL_PPOP_LO) : 32'd0);

    p = 0;
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(1 << INT_DI_BIT));
    p = place_store_abs(p, 4'd0, A_INTENB);
    p = place_word(p, setf_enc(5'd16));
    p = place_movi_il(p, 4'd0, 32'd8);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, 32'd23);
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il(p, 4'd0, control);
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_movi_il(p, 4'd0, rmw ? 32'd1 : 32'd0);
    p = place_store_abs(p, 4'd0, A_PMASK);
    p = place_movi_il(p, 4'd0,
                      srt ? (DATA_WIDTH'(1) << DPYCTL_SRT_BIT) : 32'd0);
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_movi_il_b(p, 4'd0, initial_d);
    p = place_movi_il_b(p, 4'd2, initial_daddr);
    p = place_movi_il_b(p, 4'd4, OFFSET);
    p = place_movi_il_b(p, 4'd5, {16'd8, 16'd8});
    p = place_movi_il_b(p, 4'd6, {16'd14, 16'd14});
    p = place_movi_il_b(p, 4'd7, {b, a});
    p = place_movi_il_b(p, 4'd9, 32'hAEAE_AEAE);
    p = place_movi_il_b(p, 4'd10, DATA_WIDTH'(count));
    p = place_movi_il_b(p, 4'd11, inc1);
    p = place_movi_il_b(p, 4'd12, inc2);
    // Normalize flags after signed INC setup, then enable interrupts.
    p = place_movi_il(p, 4'd14, 32'd1);
    p = place_word(p, 16'h0D60);
    line_opcode_pc = DATA_WIDTH'(p * INSTR_WORD_BITS);
    p = place_word(p, 16'hDF1A);
    p = place_word(p, 16'hC0FF);

    p = ISR_WORD;
    p = place_movi_il(p, 4'd3, 32'd0);
    p = place_store_abs(p, 4'd3, A_INTPEND);
    p = place_movi_il(p, 4'd10, 32'h0000_BEEF);
    p = place_word(p, 16'h0940);
    u_mem.mem[DI_VEC_WORD] = ISR_PC[15:0];
    u_mem.mem[DI_VEC_WORD + 1] = ISR_PC[31:16];
    u_mem.mem[NMI_VEC_WORD] = ISR_PC[15:0];
    u_mem.mem[NMI_VEC_WORD + 1] = ISR_PC[31:16];
  endtask

  task automatic run_case(
      input logic [15:0] start_x,
      input logic [15:0] start_y,
      input logic [15:0] a,
      input logic [15:0] b,
      input logic signed [15:0] inc1_x,
      input logic signed [15:0] inc1_y,
      input logic signed [15:0] inc2_x,
      input logic signed [15:0] inc2_y,
      input logic w3,
      input logic rmw,
      input logic srt,
      input logic use_nmi,
      input string label
  );
    localparam int unsigned COUNT = 8;
    logic [DATA_WIDTH-1:0] d;
    logic [DATA_WIDTH-1:0] daddr;
    logic [DATA_WIDTH-1:0] inc1;
    logic [DATA_WIDTH-1:0] inc2;
    logic [DATA_WIDTH-1:0] address;
    logic branch_step;
    logic inside_window;
    logic [7:0] initial_pixel;
    logic [7:0] final_pixel;
    logic reached_halt;

    d = DATA_WIDTH'((2 * int'(b)) - int'(a));
    daddr = {start_y, start_x};
    inc1 = {inc1_y, inc1_x};
    inc2 = {inc2_y, inc2_x};
    initial_pixel = rmw ? 8'h55 : 8'h00;
    final_pixel = rmw ? 8'hFB : 8'hAE;

    begin_case();
    build_program(d, daddr, a, b, inc1, inc2, COUNT, w3, rmw, srt);

    for (int unsigned pixel = 0; pixel < COUNT; pixel++) begin
      address = OFFSET + DATA_WIDTH'(daddr[31:16] * 256)
               + DATA_WIDTH'(daddr[15:0] * 8);
      expected_pixel_addr[pixel] = address;
      write_field(address, initial_pixel);
      inside_window = (daddr[15:0] >= 16'd8) && (daddr[15:0] <= 16'd14)
                   && (daddr[31:16] >= 16'd8)
                   && (daddr[31:16] <= 16'd14);
      expected_pixel_value[pixel] = (!w3 || inside_window)
                                  ? final_pixel : initial_pixel;
      if (rmw || w3)
        append_request(address, 1'b0, srt);
      append_request(address, 1'b1, srt);

      branch_step = !d[31] && (d != '0);
      d = branch_step
        ? d + {16'd0, b} * 2 - {16'd0, a} * 2
        : d + {16'd0, b} * 2;
      daddr = branch_step
        ? {daddr[31:16] + inc1[31:16], daddr[15:0] + inc1[15:0]}
        : {daddr[31:16] + inc2[31:16], daddr[15:0] + inc2[15:0]};
      if (pixel != COUNT - 1) begin
        expected_d[pixel] = d;
        expected_daddr[pixel] = daddr;
        expected_count[pixel] = DATA_WIDTH'(COUNT - pixel - 1);
      end
    end

    inject_nmi = use_nmi;
    inject_enable = 1'b1;
    @(negedge clk);
    rst = 1'b0;
    reached_halt = 1'b0;
    begin : wait_for_halt
      for (int unsigned cycle = 0; cycle < 80000; cycle++) begin
        @(posedge clk);
        #1;
        if ((state_w == CORE_EXECUTE) && (instr_w == 16'hC0FF)) begin
          reached_halt = 1'b1;
          disable wait_for_halt;
        end
      end
    end
    inject_enable = 1'b0;

    if (!reached_halt) begin
      $display("TEST_RESULT: FAIL: %s did not complete", label);
      failures++;
    end
    if (checkpoint_count != COUNT - 1 || interrupt_count != COUNT - 1
        || setup_count != COUNT) begin
      $display("TEST_RESULT: FAIL: %s checkpoint/entry/setup expected=7/7/8 actual=%0d/%0d/%0d",
               label, checkpoint_count, interrupt_count, setup_count);
      failures++;
    end
    if (actual_request_count != expected_request_count) begin
      $display("TEST_RESULT: FAIL: %s request count expected=%0d actual=%0d",
               label, expected_request_count, actual_request_count);
      failures++;
    end
    for (int unsigned index = 0;
         index < actual_request_count && index < expected_request_count;
         index++) begin
      if (actual_addr[index] !== expected_addr[index]
          || actual_we[index] !== expected_we[index]
          || actual_srt[index] !== expected_srt[index]) begin
        $display("TEST_RESULT: FAIL: %s request[%0d] addr=%08h/%08h we=%0b/%0b srt=%0b/%0b",
                 label, index, actual_addr[index], expected_addr[index],
                 actual_we[index], expected_we[index],
                 actual_srt[index], expected_srt[index]);
        failures++;
      end
    end
    for (int unsigned pixel = 0; pixel < COUNT; pixel++) begin
      if (read_field(expected_pixel_addr[pixel])
          !== expected_pixel_value[pixel]) begin
        $display("TEST_RESULT: FAIL: %s pixel[%0d] addr=%08h value=%02h/%02h",
                 label, pixel, expected_pixel_addr[pixel],
                 read_field(expected_pixel_addr[pixel]),
                 expected_pixel_value[pixel]);
        failures++;
      end
    end
    if (u_core.u_regfile.b_regs[0] !== d
        || u_core.u_regfile.b_regs[2] !== daddr
        || u_core.u_regfile.b_regs[10] !== 32'd0
        || u_core.u_regfile.b_regs[11] !== inc1
        || u_core.u_regfile.b_regs[12] !== inc2) begin
      $display("TEST_RESULT: FAIL: %s final B0=%08h/%08h B2=%08h/%08h B10=%08h B11=%08h/%08h B12=%08h/%08h",
               label, u_core.u_regfile.b_regs[0], d,
               u_core.u_regfile.b_regs[2], daddr,
               u_core.u_regfile.b_regs[10], u_core.u_regfile.b_regs[11],
               inc1, u_core.u_regfile.b_regs[12], inc2);
      failures++;
    end
    if (u_core.u_regfile.a_regs[10] !== 32'h0000_BEEF
        || u_core.u_regfile.sp_q !== SP_INIT
        || u_core.u_status_reg.st_q
           !== (BASE_ST | (w3 ? (DATA_WIDTH'(1) << ST_V_BIT) : 32'd0))
        || u_core.u_status_reg.st_q[ST_PBX_BIT]) begin
      $display("TEST_RESULT: FAIL: %s handler/SP/ST A10=%08h SP=%08h ST=%08h",
               label, u_core.u_regfile.a_regs[10], u_core.u_regfile.sp_q,
               u_core.u_status_reg.st_q);
      failures++;
    end
    if (protocol_error || !saw_wait || illegal_w) begin
      $display("TEST_RESULT: FAIL: %s protocol=%0b wait=%0b illegal=%0b",
               label, protocol_error, saw_wait, illegal_w);
      failures++;
    end
  endtask

  initial begin : main
    failures = 0;

    run_case(10, 10, 7, 0,  1,  1,  1,  0, 0, 0, 0, 0,
             "horizontal +X DI");
    run_case(10, 10, 7, 0,  1,  1,  0,  1, 0, 1, 1, 1,
             "vertical +Y RMW SRT NMI");
    run_case(10, 10, 7, 7,  1,  1,  1,  0, 0, 0, 0, 0,
             "diagonal +X+Y DI");
    run_case(10, 10, 7, 3,  1,  1,  1,  0, 0, 1, 0, 1,
             "shallow +X+Y RMW NMI");
    run_case(10, 10, 7, 3,  1,  1,  0,  1, 0, 0, 1, 0,
             "steep +X+Y SRT DI");
    run_case(10, 30, 7, 3,  1, -1,  1,  0, 0, 0, 0, 1,
             "shallow +X-Y NMI");
    run_case(10, 30, 7, 3,  1, -1,  0, -1, 0, 1, 0, 0,
             "steep +X-Y RMW DI");
    run_case(30, 10, 7, 3, -1,  1, -1,  0, 0, 0, 1, 1,
             "shallow -X+Y SRT NMI");
    run_case(30, 10, 7, 3, -1,  1,  0,  1, 0, 0, 0, 0,
             "steep -X+Y DI");
    run_case(30, 30, 7, 3, -1, -1, -1,  0, 0, 1, 0, 1,
             "shallow -X-Y RMW NMI");
    run_case(30, 30, 7, 3, -1, -1,  0, -1, 0, 0, 0, 0,
             "steep -X-Y DI");
    run_case(10, 10, 7, 7,  1,  1,  1,  0, 1, 0, 1, 1,
             "W3 clipped diagonal SRT NMI");

    if (failures == 0)
      $display("TEST_RESULT: PASS (LINE all-octant checkpoint interrupt/RETI continuation)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #240_000_000;
    $display("TEST_RESULT: FAIL: tb_line_interrupt hard timeout");
    $fatal(1);
  end

endmodule : tb_line_interrupt
