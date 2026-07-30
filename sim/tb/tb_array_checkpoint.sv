// -----------------------------------------------------------------------------
// tb_array_checkpoint.sv
//
// Tasks 0166-0167: architectural FILL/PIXBLT checkpoint/resume images.
//
// Every completed destination 16-bit-word or nonfinal-row boundary is followed
// by one coherent B-file checkpoint. The reference model checks the complete
// image, exact unchanged graphics traffic, and reconstructs the remaining
// request suffix using only that image plus preserved implied configuration.
// Every checkpoint is then interrupted: alternating cases use maskable DI or
// NMI (NMIM=0), a real handler preserves B state and returns through RETI, and
// the array must continue without changing the uninterrupted request oracle.
//
// Coverage:
//   * FILL L/XY and PIXBLT L,L / L,XY / XY,L / XY,XY / B,L / B,XY;
//   * first, middle, word, row, and final-instruction boundaries;
//   * forward/reverse traversal, W=0/W=3, PSIZE 2/4/8/16;
//   * direct replace and PPOP/PMASK destination-read paths, SRT marking;
//   * partial-word RMW, three inserted physical-word waits, held requests;
//   * exact final framebuffer/context and no checkpoint after the final pixel.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_array_checkpoint;
  import tms34010_pkg::*;

  localparam int unsigned MEM_WORDS = 8192;
  localparam int unsigned MAX_REQUESTS = 256;
  localparam int unsigned MAX_CHECKPOINTS = 32;

  localparam int unsigned KIND_FILL_L  = 0;
  localparam int unsigned KIND_FILL_XY = 1;
  localparam int unsigned KIND_LL      = 2;
  localparam int unsigned KIND_LXY     = 3;
  localparam int unsigned KIND_XYL     = 4;
  localparam int unsigned KIND_XYXY    = 5;
  localparam int unsigned KIND_BL      = 6;
  localparam int unsigned KIND_BXY     = 7;

  localparam logic [DATA_WIDTH-1:0] OFFSET_VAL = 32'h0000_2000;
  localparam logic [DATA_WIDTH-1:0] LINEAR_SRC_BASE = 32'h0000_A000;
  localparam logic [DATA_WIDTH-1:0] LINEAR_DST_BASE = 32'h0000_6000;
  localparam logic [DATA_WIDTH-1:0] FILL_B0_SEED = 32'h1357_9BDF;
  localparam logic [DATA_WIDTH-1:0] B13_SEED = 32'hD13D_13D1;

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
  localparam logic [DATA_WIDTH-1:0] A_INTENB =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_INTENB) << 4);
  localparam logic [DATA_WIDTH-1:0] A_INTPEND =
      IO_BASE_ADDR + (DATA_WIDTH'(IO_IDX_INTPEND) << 4);
  localparam logic [DATA_WIDTH-1:0] SP_INIT = 32'h0000_1800;
  localparam int unsigned ISR_WORD = 256;
  localparam logic [DATA_WIDTH-1:0] ISR_PC =
      DATA_WIDTH'(ISR_WORD * INSTR_WORD_BITS);
  localparam int unsigned DI_VEC_WORD =
      (INT_VEC_DI >> LOCAL_WORD_ADDR_LSB) & (MEM_WORDS - 1);
  localparam int unsigned NMI_VEC_WORD =
      (INT_VEC_NMI >> LOCAL_WORD_ADDR_LSB) & (MEM_WORDS - 1);
  localparam logic [15:0] DI_MASK = 16'(1 << INT_DI_BIT);
  // The final setup MOVI loads the negative B14 seed, so N is live when the
  // array reaches its first checkpoint and remains unaffected thereafter.
  localparam logic [DATA_WIDTH-1:0] ARRAY_ST =
      ST_RESET_VALUE | (DATA_WIDTH'(1) << ST_IE_BIT)
                     | (DATA_WIDTH'(1) << ST_N_BIT);
  localparam logic [DATA_WIDTH-1:0] ARRAY_PBX_ST =
      ARRAY_ST | (DATA_WIDTH'(1) << ST_PBX_BIT);

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
    .host_mem_ack_i(1'b0), .dpyint_set_i(dpyint_set), .refresh_req_o(),
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
      64:      pitch_shift = 6;
      128:     pitch_shift = 7;
      256:     pitch_shift = 8;
      512:     pitch_shift = 9;
      default: pitch_shift = 0;
    endcase
  endfunction

  function automatic logic [DATA_WIDTH-1:0] field_mask(
      input int unsigned size
  );
    field_mask = (32'd1 << size) - 32'd1;
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

  logic [DATA_WIDTH-1:0] snap_b0  [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b1  [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b2  [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b3  [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b7  [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b10 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b11 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b12 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b13 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] snap_b14 [0:MAX_CHECKPOINTS-1];
  int unsigned snap_req_count [0:MAX_CHECKPOINTS-1];

  logic [DATA_WIDTH-1:0] exp_b0  [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] exp_b2  [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] exp_b10 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] exp_b11 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] exp_b12 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] exp_b13 [0:MAX_CHECKPOINTS-1];
  logic [DATA_WIDTH-1:0] exp_b14 [0:MAX_CHECKPOINTS-1];
  int unsigned exp_req_count [0:MAX_CHECKPOINTS-1];

  int unsigned failures;
  int unsigned actual_count;
  int unsigned expected_count;
  int unsigned snapshot_count;
  int unsigned expected_snapshot_count;
  int unsigned interrupt_count;
  int unsigned resume_count;
  logic        inject_enable;
  logic        inject_nmi;
  logic [DATA_WIDTH-1:0] array_opcode_pc;
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
      interrupt_count   <= 0;
      resume_count      <= 0;
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

      if ((state_w == CORE_INT_PUSH_PC) && mem_ack) begin
        if (mem_addr !== (SP_INIT - WORD_BIT_SIZE)
            || mem_size !== MEM_SIZE_32
            || mem_wdata !== array_opcode_pc) begin
          $display("TEST_RESULT: FAIL: interrupt PC push addr=%08h/%08h size=%0d data=%08h/%08h",
                   mem_addr, SP_INIT - WORD_BIT_SIZE, mem_size,
                   mem_wdata, array_opcode_pc);
          failures++;
        end
      end
      if ((state_w == CORE_INT_PUSH_ST) && mem_ack) begin
        if (mem_addr !== (SP_INIT - WORD_BIT_SIZE_2)
            || mem_size !== MEM_SIZE_32
            || mem_wdata !== ARRAY_PBX_ST) begin
          $display("TEST_RESULT: FAIL: interrupt ST push addr=%08h/%08h size=%0d data=%08h/%08h",
                   mem_addr, SP_INIT - WORD_BIT_SIZE_2, mem_size, mem_wdata,
                   ARRAY_PBX_ST);
          failures++;
        end
        interrupt_count <= interrupt_count + 1;
      end
      if (state_w == CORE_ARRAY_RESUME1)
        resume_count <= resume_count + 1;
    end
  end

  // Assert the selected request early in every checkpoint serialization
  // chain. DI is sticky in INTPEND until the handler clears it. A direct-host
  // high-byte HSTCTL write sets NMI with NMIM=0; entry auto-clears it.
  always @(negedge clk) begin
    if (rst) begin
      dpyint_set = 1'b0;
      host_req   = 1'b0;
      host_we    = 1'b0;
      host_reg   = HOST_REG_HSTCTL;
      host_be    = 2'b00;
      host_wdata = 16'h0000;
    end else begin
      dpyint_set = 1'b0;
      if (host_req && host_ack) begin
        host_req = 1'b0;
        host_we  = 1'b0;
        host_be  = 2'b00;
      end
      if (inject_enable && (state_w == CORE_ARRAY_CKPT_B0)) begin
        if (inject_nmi) begin
          host_req   = 1'b1;
          host_we    = 1'b1;
          host_reg   = HOST_REG_HSTCTL;
          host_be    = 2'b10;
          host_wdata = 16'(1 << HSTCTL_NMI_BIT);
        end else begin
          dpyint_set = 1'b1;
        end
      end
    end
  end

  // B14 commits on this edge; sample after nonblocking register-file updates.
  always @(posedge clk) begin
    if (rst) begin
      snapshot_count = 0;
    end else if (u_core.array_checkpoint) begin
      #1;
      if (snapshot_count < MAX_CHECKPOINTS) begin
        snap_b0[snapshot_count]  = u_core.u_regfile.b_regs[0];
        snap_b1[snapshot_count]  = u_core.u_regfile.b_regs[1];
        snap_b2[snapshot_count]  = u_core.u_regfile.b_regs[2];
        snap_b3[snapshot_count]  = u_core.u_regfile.b_regs[3];
        snap_b7[snapshot_count]  = u_core.u_regfile.b_regs[7];
        snap_b10[snapshot_count] = u_core.u_regfile.b_regs[10];
        snap_b11[snapshot_count] = u_core.u_regfile.b_regs[11];
        snap_b12[snapshot_count] = u_core.u_regfile.b_regs[12];
        snap_b13[snapshot_count] = u_core.u_regfile.b_regs[13];
        snap_b14[snapshot_count] = u_core.u_regfile.b_regs[14];
        snap_req_count[snapshot_count] = actual_count;
      end
      snapshot_count = snapshot_count + 1;
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
    expected_snapshot_count = 0;
    inject_enable = 1'b0;
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
      input logic w3,
      input logic rmw,
      input logic srt,
      input int unsigned sptch,
      input int unsigned dptch,
      input int unsigned dx,
      input int unsigned dy,
      input logic [DATA_WIDTH-1:0] source_raw,
      input logic [DATA_WIDTH-1:0] dest_raw,
      input int unsigned dst_x,
      input int unsigned dst_y
  );
    int unsigned p;
    instr_word_t opcode;
    logic [DATA_WIDTH-1:0] control;
    int unsigned wx0;
    int unsigned wx1;

    unique case (kind)
      KIND_FILL_L:  opcode = 16'h0FC0;
      KIND_FILL_XY: opcode = 16'h0FE0;
      KIND_LL:      opcode = 16'h0F00;
      KIND_LXY:     opcode = 16'h0F20;
      KIND_XYL:     opcode = 16'h0F40;
      KIND_XYXY:    opcode = 16'h0F60;
      KIND_BL:      opcode = 16'h0F80;
      default:      opcode = 16'h0FA0;
    endcase
    control = (DATA_WIDTH'(w3 ? 3 : 0) << CTRL_W_LO)
            | (DATA_WIDTH'(hrev) << CTRL_PBH_BIT)
            | (DATA_WIDTH'(vrev) << CTRL_PBV_BIT)
            | (rmw ? (DATA_WIDTH'(5'h0A) << CTRL_PPOP_LO) : 32'd0);
    wx0 = dst_x + (w3 ? 1 : 0);
    wx1 = dst_x + dx - 1;

    p = 0;
    p = place_movi_il(p, 4'd2, SP_INIT);
    p = place_word(p, 16'h4C4F);
    p = place_movi_il(p, 4'd0, {16'h0000, DI_MASK});
    p = place_store_abs(p, 4'd0, A_INTENB);
    p = place_word(p, 16'h0D60);
    p = place_word(p, setf_enc(5'd16));
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(psize));
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(31 - pitch_shift(sptch)));
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_movi_il(p, 4'd0, DATA_WIDTH'(31 - pitch_shift(dptch)));
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il(p, 4'd0, control);
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_movi_il(p, 4'd0, rmw ? 32'h0000_0001 : 32'd0);
    p = place_store_abs(p, 4'd0, A_PMASK);
    p = place_movi_il(p, 4'd0,
                      srt ? (DATA_WIDTH'(1) << DPYCTL_SRT_BIT) : 32'd0);
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_movi_il_b(p, 4'd0,
                        ((kind == KIND_FILL_L) || (kind == KIND_FILL_XY))
                        ? FILL_B0_SEED : source_raw);
    p = place_movi_il_b(p, 4'd1, DATA_WIDTH'(sptch));
    p = place_movi_il_b(p, 4'd2, dest_raw);
    p = place_movi_il_b(p, 4'd3, DATA_WIDTH'(dptch));
    p = place_movi_il_b(p, 4'd4, OFFSET_VAL);
    p = place_movi_il_b(p, 4'd5, {16'(dst_y), 16'(wx0)});
    p = place_movi_il_b(p, 4'd6,
                        {16'(dst_y + dy - 1), 16'(wx1)});
    p = place_movi_il_b(p, 4'd7, {16'(dy), 16'(dx)});
    p = place_movi_il_b(p, 4'd8, 32'h0000_0003);
    p = place_movi_il_b(p, 4'd9, 32'h0000_00AE);
    p = place_movi_il_b(p, 4'd10, 32'hA010_A010);
    p = place_movi_il_b(p, 4'd11, 32'hA011_A011);
    p = place_movi_il_b(p, 4'd12, 32'hA012_A012);
    p = place_movi_il_b(p, 4'd13, B13_SEED);
    p = place_movi_il_b(p, 4'd14, 32'hA014_A014);
    array_opcode_pc = DATA_WIDTH'(p * INSTR_WORD_BITS);
    p = place_word(p, opcode);
    p = place_word(p, 16'hC0FF);

    // Shared handler: clear any maskable source, leave all B registers
    // untouched, publish a marker in A10, and restore PC/ST through RETI.
    p = ISR_WORD;
    p = place_movi_il(p, 4'd3, 32'd0);
    p = place_store_abs(p, 4'd3, A_INTPEND);
    p = place_movi_il(p, 4'd10, 32'h0000_BEEF);
    p = place_word(p, 16'h0940);
    u_mem.mem[DI_VEC_WORD]     = ISR_PC[15:0];
    u_mem.mem[DI_VEC_WORD + 1] = ISR_PC[31:16];
    u_mem.mem[NMI_VEC_WORD]     = ISR_PC[15:0];
    u_mem.mem[NMI_VEC_WORD + 1] = ISR_PC[31:16];
  endtask

  task automatic launch_and_wait(input string label);
    logic reached_loop;
    reached_loop = 1'b0;
    @(negedge clk);
    rst = 1'b0;
    begin : wait_cycles
      for (int unsigned cycle = 0; cycle < 40000; cycle++) begin
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

  task automatic compare_request(
      input int unsigned index,
      input logic [DATA_WIDTH-1:0] addr,
      input logic we,
      input int unsigned size,
      input logic srt,
      input string label,
      input string scope
  );
    if (index >= expected_count
        || expected_addr[index] !== addr
        || expected_we[index] !== we
        || expected_size[index] !== FIELD_SIZE_WIDTH'(size)
        || expected_srt[index] !== srt) begin
      $display("TEST_RESULT: FAIL: %s %s request[%0d] addr=%08h expected=%08h we=%0b/%0b size=%0d/%0d srt=%0b/%0b",
               label, scope, index, addr,
               (index < expected_count) ? expected_addr[index] : 32'hDEAD_DEAD,
               we, (index < expected_count) ? expected_we[index] : 1'bx,
               size, (index < expected_count) ? expected_size[index] : 'x,
               srt, (index < expected_count) ? expected_srt[index] : 1'bx);
      failures++;
    end
  endtask

  task automatic run_case(
      input int unsigned kind,
      input int unsigned psize,
      input logic hrev_in,
      input logic vrev_in,
      input logic w3,
      input logic rmw,
      input logic srt,
      input logic use_nmi,
      input string label
  );
    localparam int unsigned DX = 5;
    localparam int unsigned DY = 3;
    localparam int unsigned SPTCH = 128;
    localparam int unsigned DPTCH = 256;
    logic is_fill;
    logic binary;
    logic src_xy;
    logic dst_xy;
    logic hrev;
    logic vrev;
    int unsigned coord_x;
    int unsigned src_y;
    int unsigned dst_y;
    int unsigned work_dx;
    int unsigned work_dy;
    int unsigned clip_left;
    int unsigned source_step;
    int unsigned logical_row;
    int unsigned logical_col;
    int unsigned next_x;
    int unsigned next_y;
    int unsigned next_logical_row;
    int unsigned next_logical_col;
    logic row_end;
    logic final_pixel;
    logic checkpoint_due;
    logic [DATA_WIDTH-1:0] align_offset;
    logic [DATA_WIDTH-1:0] source_raw;
    logic [DATA_WIDTH-1:0] dest_raw;
    logic [DATA_WIDTH-1:0] source_top;
    logic [DATA_WIDTH-1:0] dest_top;
    logic [DATA_WIDTH-1:0] work_source_top;
    logic [DATA_WIDTH-1:0] work_dest_top;
    logic [DATA_WIDTH-1:0] work_raw_dest;
    logic [DATA_WIDTH-1:0] source_addr;
    logic [DATA_WIDTH-1:0] dest_addr;
    logic [DATA_WIDTH-1:0] next_source_addr;
    logic [DATA_WIDTH-1:0] next_dest_addr;
    logic [DATA_WIDTH-1:0] fill_final;
    logic [DATA_WIDTH-1:0] pblt_src_final;
    logic [DATA_WIDTH-1:0] pblt_dst_final;
    logic [DATA_WIDTH-1:0] initial_dest;
    logic [DATA_WIDTH-1:0] expected_pixel;
    logic [DATA_WIDTH-1:0] actual_pixel;
    logic [DATA_WIDTH-1:0] source_value;
    logic [DATA_WIDTH-1:0] mask;
    int unsigned expected_index;
    int unsigned cursor_x;
    int unsigned cursor_y;
    logic [DATA_WIDTH-1:0] restart_source;
    logic [DATA_WIDTH-1:0] restart_dest;
    logic [DATA_WIDTH-1:0] source_row_start;
    logic [DATA_WIDTH-1:0] dest_row_start;

    is_fill = (kind == KIND_FILL_L) || (kind == KIND_FILL_XY);
    binary = (kind == KIND_BL) || (kind == KIND_BXY);
    src_xy = (kind == KIND_XYL) || (kind == KIND_XYXY);
    dst_xy = (kind == KIND_FILL_XY) || (kind == KIND_LXY)
          || (kind == KIND_XYXY) || (kind == KIND_BXY);
    hrev = hrev_in && !is_fill && !binary;
    vrev = vrev_in && !is_fill && !binary;
    coord_x = (psize < 16) ? (8 / psize) : 0;
    src_y = 2;
    dst_y = 16;
    align_offset = (psize < 16) ? 32'd8 : 32'd0;
    source_step = binary ? 1 : psize;
    clip_left = w3 ? 1 : 0;
    work_dx = DX - clip_left;
    work_dy = DY;
    source_raw = src_xy ? {16'(src_y), 16'(coord_x)}
                        : LINEAR_SRC_BASE + align_offset;
    dest_raw = dst_xy ? {16'(dst_y), 16'(coord_x)}
                      : LINEAR_DST_BASE + align_offset;
    source_top = src_xy
               ? OFFSET_VAL + DATA_WIDTH'(src_y * SPTCH + coord_x * psize)
               : LINEAR_SRC_BASE + align_offset;
    dest_top = dst_xy
             ? OFFSET_VAL + DATA_WIDTH'(dst_y * DPTCH + coord_x * psize)
             : LINEAR_DST_BASE + align_offset;
    work_source_top = source_top + DATA_WIDTH'(clip_left * source_step);
    work_dest_top = dest_top + DATA_WIDTH'(clip_left * psize);
    work_raw_dest = dst_xy
                  ? {16'(dst_y), 16'(coord_x + clip_left)} : dest_raw;
    fill_final = dest_top + DATA_WIDTH'((DY - 1) * DPTCH + DX * psize);
    pblt_src_final = source_top + DATA_WIDTH'(DY * SPTCH);
    pblt_dst_final = dest_top + DATA_WIDTH'(DY * DPTCH);
    mask = field_mask(psize);
    initial_dest = rmw ? (32'h0000_0055 & mask) : 32'd0;

    begin_case();
    build_program(kind, psize, hrev_in, vrev_in, w3, rmw, srt,
                  SPTCH, DPTCH, DX, DY, source_raw, dest_raw,
                  coord_x, dst_y);
    inject_nmi = use_nmi;
    inject_enable = 1'b1;

    for (int unsigned row = 0; row < DY; row++) begin
      for (int unsigned col = 0; col < DX; col++) begin
        dest_addr = dest_top + DATA_WIDTH'(row * DPTCH + col * psize);
        write_field(dest_addr, psize, initial_dest);
        if (!is_fill) begin
          source_addr = source_top
                      + DATA_WIDTH'(row * SPTCH + col * source_step);
          source_value = binary ? DATA_WIDTH'((row * DX + col) & 1)
                                : DATA_WIDTH'(1 + row * DX + col);
          write_field(source_addr, source_step, source_value);
        end
      end
    end

    // Reference traffic and coherent checkpoint images.
    for (int unsigned row = 0; row < work_dy; row++) begin
      logical_row = vrev ? work_dy - 1 - row : row;
      for (int unsigned col = 0; col < work_dx; col++) begin
        logical_col = hrev ? work_dx - 1 - col : col;
        source_addr = work_source_top
                    + DATA_WIDTH'(logical_row * SPTCH
                                + logical_col * source_step);
        dest_addr = work_dest_top
                  + DATA_WIDTH'(logical_row * DPTCH
                              + logical_col * psize);
        if (is_fill) begin
          if (rmw) append_request(dest_addr, 1'b0, psize, srt);
          append_request(dest_addr, 1'b1, psize, srt);
        end else begin
          append_request(source_addr, 1'b0, source_step, srt);
          if (rmw) append_request(dest_addr, 1'b0, psize, srt);
          append_request(dest_addr, 1'b1, psize, srt);
        end

        row_end = (col == work_dx - 1);
        final_pixel = row_end && (row == work_dy - 1);
        checkpoint_due = !final_pixel
            && (row_end
                || (hrev ? (dest_addr[3:0] == 4'd0)
                          : (((dest_addr + DATA_WIDTH'(psize))
                              & 32'h0000_000F) == 32'd0)));
        if (checkpoint_due) begin
          next_x = row_end ? 0 : col + 1;
          next_y = row_end ? row + 1 : row;
          next_logical_row = vrev ? work_dy - 1 - next_y : next_y;
          next_logical_col = hrev ? work_dx - 1 - next_x : next_x;
          next_source_addr = work_source_top
              + DATA_WIDTH'(next_logical_row * SPTCH
                          + next_logical_col * source_step);
          next_dest_addr = work_dest_top
              + DATA_WIDTH'(next_logical_row * DPTCH
                          + next_logical_col * psize);
          exp_b0[expected_snapshot_count] = is_fill
              ? FILL_B0_SEED : next_source_addr;
          exp_b2[expected_snapshot_count] = next_dest_addr;
          exp_b10[expected_snapshot_count] = {16'(next_y), 16'(next_x)};
          exp_b11[expected_snapshot_count] = {16'(work_dy), 16'(work_dx)};
          exp_b12[expected_snapshot_count] = is_fill
              ? (w3 ? fill_final : dest_top)
              : (w3 ? pblt_src_final
                    : source_top + DATA_WIDTH'(next_y * SPTCH));
          exp_b13[expected_snapshot_count] = is_fill
              ? B13_SEED
              : (w3 ? pblt_dst_final
                    : dest_top + DATA_WIDTH'(next_y * DPTCH));
          exp_b14[expected_snapshot_count] = work_raw_dest;
          exp_req_count[expected_snapshot_count] = expected_count;
          expected_snapshot_count++;
        end
      end
    end

    launch_and_wait(label);
    inject_enable = 1'b0;

    if (actual_count != expected_count) begin
      $display("TEST_RESULT: FAIL: %s request count expected=%0d actual=%0d",
               label, expected_count, actual_count);
      failures++;
    end
    for (int unsigned i = 0;
         (i < actual_count) && (i < expected_count) && (i < MAX_REQUESTS);
         i++) begin
      compare_request(i, actual_addr[i], actual_we[i],
                      int'(actual_size[i]),
                      actual_srt[i], label, "execution");
    end
    if (snapshot_count != expected_snapshot_count) begin
      $display("TEST_RESULT: FAIL: %s checkpoint count expected=%0d actual=%0d",
               label, expected_snapshot_count, snapshot_count);
      failures++;
    end
    if (interrupt_count != expected_snapshot_count
        || resume_count != expected_snapshot_count) begin
      $display("TEST_RESULT: FAIL: %s interrupt/resume count expected=%0d entry=%0d resume=%0d",
               label, expected_snapshot_count, interrupt_count, resume_count);
      failures++;
    end

    for (int unsigned c = 0;
         (c < snapshot_count) && (c < expected_snapshot_count);
         c++) begin
      if (snap_b0[c] !== exp_b0[c] || snap_b2[c] !== exp_b2[c]
          || snap_b10[c] !== exp_b10[c] || snap_b11[c] !== exp_b11[c]
          || snap_b12[c] !== exp_b12[c] || snap_b13[c] !== exp_b13[c]
          || snap_b14[c] !== exp_b14[c]
          || snap_b1[c] !== DATA_WIDTH'(SPTCH)
          || snap_b3[c] !== DATA_WIDTH'(DPTCH)
          || snap_b7[c] !== {16'(DY), 16'(DX)}
          || snap_req_count[c] != exp_req_count[c]) begin
        $display("TEST_RESULT: FAIL: %s checkpoint[%0d] B0=%08h/%08h B2=%08h/%08h B10=%08h/%08h B11=%08h/%08h B12=%08h/%08h B13=%08h/%08h B14=%08h/%08h req=%0d/%0d",
                 label, c, snap_b0[c], exp_b0[c], snap_b2[c], exp_b2[c],
                 snap_b10[c], exp_b10[c], snap_b11[c], exp_b11[c],
                 snap_b12[c], exp_b12[c], snap_b13[c], exp_b13[c],
                 snap_b14[c], exp_b14[c], snap_req_count[c],
                 exp_req_count[c]);
        failures++;
      end

      // Reconstruct every remaining request from this checkpoint image.
      expected_index = snap_req_count[c];
      cursor_x = int'(snap_b10[c][15:0]);
      cursor_y = int'(snap_b10[c][31:16]);
      restart_source = snap_b0[c];
      restart_dest = snap_b2[c];
      while (cursor_y < snap_b11[c][31:16]) begin
        if (is_fill) begin
          if (rmw) begin
            compare_request(expected_index, restart_dest, 1'b0, psize, srt,
                            label, "restart");
            expected_index++;
          end
          compare_request(expected_index, restart_dest, 1'b1, psize, srt,
                          label, "restart");
          expected_index++;
        end else begin
          compare_request(expected_index, restart_source, 1'b0, source_step,
                          srt, label, "restart");
          expected_index++;
          if (rmw) begin
            compare_request(expected_index, restart_dest, 1'b0, psize, srt,
                            label, "restart");
            expected_index++;
          end
          compare_request(expected_index, restart_dest, 1'b1, psize, srt,
                          label, "restart");
          expected_index++;
        end

        if (cursor_x == int'(snap_b11[c][15:0]) - 1) begin
          source_row_start = hrev
              ? restart_source + DATA_WIDTH'(cursor_x * source_step)
              : restart_source - DATA_WIDTH'(cursor_x * source_step);
          dest_row_start = hrev
              ? restart_dest + DATA_WIDTH'(cursor_x * psize)
              : restart_dest - DATA_WIDTH'(cursor_x * psize);
          restart_source = vrev
              ? source_row_start - DATA_WIDTH'(SPTCH)
              : source_row_start + DATA_WIDTH'(SPTCH);
          restart_dest = vrev
              ? dest_row_start - DATA_WIDTH'(DPTCH)
              : dest_row_start + DATA_WIDTH'(DPTCH);
          cursor_x = 0;
          cursor_y++;
        end else begin
          restart_source = hrev
              ? restart_source - DATA_WIDTH'(source_step)
              : restart_source + DATA_WIDTH'(source_step);
          restart_dest = hrev
              ? restart_dest - DATA_WIDTH'(psize)
              : restart_dest + DATA_WIDTH'(psize);
          cursor_x++;
        end
      end
      if (expected_index != expected_count) begin
        $display("TEST_RESULT: FAIL: %s checkpoint[%0d] restart suffix ended %0d/%0d",
                 label, c, expected_index, expected_count);
        failures++;
      end
    end

    for (int unsigned row = 0; row < DY; row++) begin
      for (int unsigned col = 0; col < DX; col++) begin
        dest_addr = dest_top + DATA_WIDTH'(row * DPTCH + col * psize);
        if (!w3 || (col >= clip_left)) begin
          if (is_fill) begin
            expected_pixel = 32'h0000_00AE & mask;
          end else if (binary) begin
            expected_pixel = (((row * DX + col) & 1) != 0)
                           ? (32'h0000_00AE & mask)
                           : (32'h0000_0003 & mask);
          end else begin
            expected_pixel = DATA_WIDTH'(1 + row * DX + col) & mask;
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
          $display("TEST_RESULT: FAIL: %s pixel[%0d,%0d]=%08h/%08h",
                   label, row, col, actual_pixel, expected_pixel);
          failures++;
        end
      end
    end

    if (u_core.u_regfile.b_regs[0]
        !== (is_fill ? FILL_B0_SEED : pblt_src_final)
        || u_core.u_regfile.b_regs[2]
           !== (is_fill ? fill_final : pblt_dst_final)
        || u_core.u_regfile.b_regs[7] !== {16'(DY), 16'(DX)}) begin
      $display("TEST_RESULT: FAIL: %s final context B0=%08h B2=%08h B7=%08h",
               label, u_core.u_regfile.b_regs[0],
               u_core.u_regfile.b_regs[2], u_core.u_regfile.b_regs[7]);
      failures++;
    end
    if (u_core.u_regfile.a_regs[10] !== 32'h0000_BEEF
        || u_core.u_regfile.sp_q !== SP_INIT
        || u_core.u_status_reg.st_q
           !== (ARRAY_ST | (w3 ? (DATA_WIDTH'(1) << ST_V_BIT) : 32'd0))) begin
      $display("TEST_RESULT: FAIL: %s handler/RETI A10=%08h SP=%08h ST=%08h",
               label, u_core.u_regfile.a_regs[10], u_core.u_regfile.sp_q,
               u_core.u_status_reg.st_q);
      failures++;
    end
    if (protocol_error || !saw_graphics_wait || (illegal_w !== 1'b0)) begin
      $display("TEST_RESULT: FAIL: %s protocol=%0b wait=%0b illegal=%0b",
               label, protocol_error, saw_graphics_wait, illegal_w);
      failures++;
    end
  endtask

  initial begin : main
    failures = 0;

    run_case(KIND_FILL_L, 8, 0, 0, 0, 0, 0, 0, "FILL L direct DI");
    run_case(KIND_FILL_XY, 4, 1, 1, 1, 1, 1, 1,
             "FILL XY W3 PPOP/PMASK SRT");
    run_case(KIND_LL, 16, 0, 0, 0, 0, 0, 0, "PIXBLT L,L direct DI");
    run_case(KIND_LXY, 8, 1, 0, 1, 0, 0, 1, "PIXBLT L,XY W3 PBH NMI");
    run_case(KIND_XYL, 4, 0, 1, 0, 1, 0, 0, "PIXBLT XY,L PBV RMW DI");
    run_case(KIND_XYXY, 8, 1, 1, 1, 1, 1, 1,
             "PIXBLT XY,XY W3 PBH/PBV RMW SRT");
    run_case(KIND_BL, 2, 1, 1, 0, 0, 0, 0,
             "PIXBLT B,L PB isolation DI");
    run_case(KIND_BXY, 16, 1, 1, 1, 1, 0, 1,
             "PIXBLT B,XY W3 PB isolation RMW");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (FILL/PIXBLT checkpoint interrupt/PBX/RETI resume)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #180_000_000;
    $display("TEST_RESULT: FAIL: tb_array_checkpoint hard timeout");
    $fatal(1);
  end

endmodule : tb_array_checkpoint
