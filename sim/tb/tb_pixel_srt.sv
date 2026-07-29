// -----------------------------------------------------------------------------
// tb_pixel_srt.sv
//
// End-to-end DPYCTL.SRT regression. A real program enables program-controlled
// VRAM transfers, performs PIXT and FILL operations, and then disables SRT.
// The system controller boundary must expose graphics reads/writes as MTR/RTM
// cycles while instruction fetches, immediate words, I/O, and ordinary MOVE
// traffic retain their normal cycle kinds.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixel_srt;
  import tms34010_pkg::*;

  localparam int unsigned DEPTH_WORDS = 512;
  localparam logic [ADDR_WIDTH-1:0] RESET_VECTOR_HIGH_ADDR =
      RESET_VECTOR_ADDR + ADDR_WIDTH'(LOCAL_WORD_WIDTH);
  localparam logic [ADDR_WIDTH-1:0] A_PSIZE =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PSIZE) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [ADDR_WIDTH-1:0] PIXT_ADDR = 32'h0000_0800;
  localparam logic [ADDR_WIDTH-1:0] FILL_ADDR0 = 32'h0000_0900;
  localparam logic [ADDR_WIDTH-1:0] FILL_ADDR1 = 32'h0000_0910;
  localparam logic [ADDR_WIDTH-1:0] MOVE_ADDR = 32'h0000_0A00;
  localparam logic [ADDR_WIDTH-1:0] PARTIAL_ADDR = 32'h0000_0B00;
  localparam logic [15:0] DPYCTL_SRT =
      16'h0001 << DPYCTL_SRT_BIT;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                      cycle_req;
  local_cycle_kind_t         cycle_kind;
  logic [ADDR_WIDTH-1:0]     cycle_addr;
  local_word_t               cycle_wdata;
  local_word_t               cycle_io_rdata;
  logic                      cycle_iaq;
  logic [13:0]               cycle_srfaddr;
  logic [15:0]               cycle_dpytap;
  logic                      cycle_screen_org;
  logic [7:0]                cycle_dram_row;
  local_word_t               cycle_rdata;
  logic                      cycle_ack;
  core_state_t               core_state;
  logic [ADDR_WIDTH-1:0]     pc;
  instr_word_t               instr_word;
  logic                      illegal_opcode;

  tms34010_system u_system (
    .clk               (clk),
    .vclk_i            (clk),
    .rst               (rst), .vclk_rst_i(rst),
    .video_hsync_n_i   (1'b1),
    .video_vsync_n_i   (1'b1),
    .run_emu_n_i       (1'b1),
    .emua_n_o          (),
    .hcs_n_i           (1'b0),
    .host_req_i        (1'b0),
    .host_we_i         (1'b0),
    .host_reg_i        (HOST_REG_HSTCTL),
    .host_be_i         (2'b00),
    .host_wdata_i      (16'h0000),
    .host_rdata_o      (),
    .host_ack_o        (),
    .host_busy_o       (),
    .hint_n_o          (),
    .lint1_n_i         (1'b1),
    .lint2_n_i         (1'b1),
    .dpyint_set_i      (1'b0),
    .hold_req_i        (1'b0),
    .hold_ack_o        (),
    .video_hsync_o     (),
    .video_vsync_o     (),
    .video_hblank_o    (),
    .video_vblank_o    (),
    .video_blank_o     (),
    .video_hsync_oe_o  (),
    .video_vsync_oe_o  (),
    .cycle_req_o       (cycle_req),
    .cycle_kind_o      (cycle_kind),
    .cycle_addr_o      (cycle_addr),
    .cycle_wdata_o     (cycle_wdata),
    .cycle_io_rdata_o  (cycle_io_rdata),
    .cycle_iaq_o       (cycle_iaq),
    .cycle_srfaddr_o   (cycle_srfaddr),
    .cycle_dpytap_o    (cycle_dpytap),
    .cycle_screen_org_o(cycle_screen_org),
    .cycle_dram_row_o  (cycle_dram_row),
    .cycle_rdata_i     (cycle_rdata),
    .cycle_ack_i       (cycle_ack),
    .state_o           (core_state),
    .pc_o              (pc),
    .instr_word_o      (instr_word),
    .illegal_opcode_o  (illegal_opcode)
  );

  local_word_t memory [0:DEPTH_WORDS-1];

  typedef enum logic [1:0] {
    TARGET_IDLE = 2'd0,
    TARGET_WAIT = 2'd1,
    TARGET_ACK  = 2'd2
  } target_state_t;

  target_state_t             target_state_q;
  local_cycle_kind_t         target_kind_q;
  logic [ADDR_WIDTH-1:0]     target_addr_q;
  local_word_t               target_wdata_q;
  local_word_t               target_io_rdata_q;
  logic                      target_iaq_q;
  logic [13:0]               target_srfaddr_q;
  logic [15:0]               target_dpytap_q;
  logic                      target_screen_org_q;
  logic [7:0]                target_dram_row_q;
  logic [$clog2(DEPTH_WORDS)-1:0] target_word_index;

  int unsigned mtr_count_q;
  int unsigned rtm_count_q;
  int unsigned pixel_protocol_failures_q;
  int unsigned controller_protocol_failures_q;
  int unsigned pixt_rtm_count_q;
  int unsigned fill0_rtm_count_q;
  int unsigned fill1_rtm_count_q;
  int unsigned partial_mtr_count_q;
  int unsigned partial_rtm_count_q;
  int unsigned move_write_count_q;
  int unsigned move_read_count_q;
  int unsigned restored_word_write_count_q;
  logic        opcode_iaq_seen_q;
  logic        immediate_noniaq_seen_q;

  assign target_word_index =
      target_addr_q[$clog2(DEPTH_WORDS)+LOCAL_WORD_ADDR_LSB-1
                    : LOCAL_WORD_ADDR_LSB];
  assign cycle_ack = (target_state_q == TARGET_ACK);

  always_comb begin
    cycle_rdata = '0;
    if ((target_kind_q == LOCAL_CYCLE_WORD_READ)
        && ((target_addr_q == RESET_VECTOR_ADDR)
            || (target_addr_q == RESET_VECTOR_HIGH_ADDR))) begin
      cycle_rdata = 16'h0000;
    end else if ((target_kind_q == LOCAL_CYCLE_WORD_READ)
                 && (int'(target_word_index) < DEPTH_WORDS)) begin
      cycle_rdata = memory[target_word_index];
    end else if (target_kind_q == LOCAL_CYCLE_IO_READ) begin
      cycle_rdata = target_io_rdata_q;
    end
    // LOCAL_CYCLE_PIXEL_MTR deliberately returns zero: the VRAM serial
    // register is loaded externally and no pixel value appears on LAD.
  end

  // Fixed one-clock target delay checks that every controller payload remains
  // stable through acknowledgement.
  always @(posedge clk) begin
    if (rst) begin
      target_state_q                 <= TARGET_IDLE;
      target_kind_q                  <= LOCAL_CYCLE_WORD_READ;
      target_addr_q                  <= '0;
      target_wdata_q                 <= '0;
      target_io_rdata_q              <= '0;
      target_iaq_q                   <= 1'b0;
      target_srfaddr_q               <= '0;
      target_dpytap_q                <= '0;
      target_screen_org_q            <= 1'b0;
      target_dram_row_q              <= '0;
      mtr_count_q                    <= 0;
      rtm_count_q                    <= 0;
      pixel_protocol_failures_q      <= 0;
      controller_protocol_failures_q <= 0;
      pixt_rtm_count_q               <= 0;
      fill0_rtm_count_q              <= 0;
      fill1_rtm_count_q              <= 0;
      partial_mtr_count_q            <= 0;
      partial_rtm_count_q            <= 0;
      move_write_count_q             <= 0;
      move_read_count_q              <= 0;
      restored_word_write_count_q    <= 0;
      opcode_iaq_seen_q              <= 1'b0;
      immediate_noniaq_seen_q        <= 1'b0;
    end else begin
      unique case (target_state_q)
        TARGET_IDLE: begin
          if (cycle_req) begin
            target_kind_q       <= cycle_kind;
            target_addr_q       <= cycle_addr;
            target_wdata_q      <= cycle_wdata;
            target_io_rdata_q   <= cycle_io_rdata;
            target_iaq_q        <= cycle_iaq;
            target_srfaddr_q    <= cycle_srfaddr;
            target_dpytap_q     <= cycle_dpytap;
            target_screen_org_q <= cycle_screen_org;
            target_dram_row_q   <= cycle_dram_row;

            if ((cycle_kind == LOCAL_CYCLE_PIXEL_MTR)
                || (cycle_kind == LOCAL_CYCLE_PIXEL_RTM)) begin
              if (cycle_iaq)
                pixel_protocol_failures_q <=
                    pixel_protocol_failures_q + 1;
              if ((cycle_addr != PIXT_ADDR)
                  && (cycle_addr != FILL_ADDR0)
                  && (cycle_addr != FILL_ADDR1)
                  && (cycle_addr != PARTIAL_ADDR))
                pixel_protocol_failures_q <=
                    pixel_protocol_failures_q + 1;
            end

            if (cycle_kind == LOCAL_CYCLE_PIXEL_MTR)
              mtr_count_q <= mtr_count_q + 1;
            if (cycle_kind == LOCAL_CYCLE_PIXEL_RTM)
              rtm_count_q <= rtm_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_PIXEL_RTM)
                && (cycle_addr == PIXT_ADDR))
              pixt_rtm_count_q <= pixt_rtm_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_PIXEL_RTM)
                && (cycle_addr == FILL_ADDR0))
              fill0_rtm_count_q <= fill0_rtm_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_PIXEL_RTM)
                && (cycle_addr == FILL_ADDR1))
              fill1_rtm_count_q <= fill1_rtm_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_PIXEL_MTR)
                && (cycle_addr == PARTIAL_ADDR))
              partial_mtr_count_q <= partial_mtr_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_PIXEL_RTM)
                && (cycle_addr == PARTIAL_ADDR))
              partial_rtm_count_q <= partial_rtm_count_q + 1;

            if ((cycle_kind == LOCAL_CYCLE_WORD_WRITE)
                && (cycle_addr == MOVE_ADDR))
              move_write_count_q <= move_write_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_WORD_READ)
                && (cycle_addr == MOVE_ADDR))
              move_read_count_q <= move_read_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_WORD_WRITE)
                && (cycle_addr == PIXT_ADDR))
              restored_word_write_count_q <=
                  restored_word_write_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_WORD_READ)
                && (cycle_addr == 32'h0000_0000)
                && cycle_iaq)
              opcode_iaq_seen_q <= 1'b1;
            if ((cycle_kind == LOCAL_CYCLE_WORD_READ)
                && (cycle_addr == 32'h0000_0020)
                && !cycle_iaq)
              immediate_noniaq_seen_q <= 1'b1;

            target_state_q <= TARGET_WAIT;
          end
        end

        TARGET_WAIT: begin
          if (!cycle_req
              || (cycle_kind != target_kind_q)
              || (cycle_addr != target_addr_q)
              || (cycle_wdata != target_wdata_q)
              || (cycle_io_rdata != target_io_rdata_q)
              || (cycle_iaq != target_iaq_q)
              || (cycle_srfaddr != target_srfaddr_q)
              || (cycle_dpytap != target_dpytap_q)
              || (cycle_screen_org != target_screen_org_q)
              || (cycle_dram_row != target_dram_row_q)) begin
            controller_protocol_failures_q <=
                controller_protocol_failures_q + 1;
          end

          if ((target_kind_q == LOCAL_CYCLE_WORD_WRITE)
              && (int'(target_word_index) < DEPTH_WORDS))
            memory[target_word_index] <= target_wdata_q;
          target_state_q <= TARGET_ACK;
        end

        TARGET_ACK: begin
          // Keep acknowledge asserted until the request owner observes it
          // and withdraws the held command. This prevents the same request
          // from being accepted again during the response turn-around.
          if (!cycle_req) begin
            target_state_q <= TARGET_IDLE;
          end else if ((cycle_kind != target_kind_q)
                       || (cycle_addr != target_addr_q)
                       || (cycle_wdata != target_wdata_q)
                       || (cycle_io_rdata != target_io_rdata_q)
                       || (cycle_iaq != target_iaq_q)
                       || (cycle_srfaddr != target_srfaddr_q)
                       || (cycle_dpytap != target_dpytap_q)
                       || (cycle_screen_org != target_screen_org_q)
                       || (cycle_dram_row != target_dram_row_q)) begin
            controller_protocol_failures_q <=
                controller_protocol_failures_q + 1;
          end
        end

        default: target_state_q <= TARGET_IDLE;
      endcase
    end
  end

  function automatic instr_word_t movi_il_enc(input reg_idx_t idx);
    return 16'h09E0 | instr_word_t'(idx);
  endfunction

  function automatic instr_word_t movi_il_b_enc(input reg_idx_t idx);
    return 16'h09F0 | instr_word_t'(idx);
  endfunction

  function automatic instr_word_t setf_enc(
    input logic [4:0] fs,
    input logic       fe,
    input logic       f_sel
  );
    return 16'b0000_0100_0000_0000
         | (instr_word_t'(f_sel) << 9)
         | 16'b0000_0001_0000_0000
         | 16'b0000_0000_0100_0000
         | (instr_word_t'(fe) << 5)
         | instr_word_t'(fs);
  endfunction

  function automatic instr_word_t pixt_store_enc(
    input reg_idx_t source,
    input reg_idx_t address
  );
    return 16'hF800
         | (instr_word_t'(source) << 5)
         | instr_word_t'(address);
  endfunction

  function automatic instr_word_t pixt_load_enc(
    input reg_idx_t address,
    input reg_idx_t destination
  );
    return 16'hFA00
         | (instr_word_t'(address) << 5)
         | instr_word_t'(destination);
  endfunction

  function automatic int unsigned place_word(
    input int unsigned p,
    input instr_word_t value
  );
    memory[p] = value;
    return p + 1;
  endfunction

  function automatic int unsigned place_movi_il(
    input int unsigned p,
    input reg_idx_t    idx,
    input logic [DATA_WIDTH-1:0] immediate
  );
    memory[p]     = movi_il_enc(idx);
    memory[p + 1] = immediate[15:0];
    memory[p + 2] = immediate[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_movi_il_b(
    input int unsigned p,
    input reg_idx_t    idx,
    input logic [DATA_WIDTH-1:0] immediate
  );
    memory[p]     = movi_il_b_enc(idx);
    memory[p + 1] = immediate[15:0];
    memory[p + 2] = immediate[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_store_abs(
    input int unsigned p,
    input reg_idx_t    source,
    input logic [ADDR_WIDTH-1:0] address
  );
    memory[p]     = 16'h0580 | instr_word_t'(source);
    memory[p + 1] = address[15:0];
    memory[p + 2] = address[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_load_abs(
    input int unsigned p,
    input reg_idx_t    destination,
    input logic [ADDR_WIDTH-1:0] address
  );
    memory[p]     = 16'h05A0 | instr_word_t'(destination);
    memory[p + 1] = address[15:0];
    memory[p + 2] = address[31:16];
    return p + 3;
  endfunction

  int unsigned failures;

  task automatic check_count(
    input string       label,
    input int unsigned actual,
    input int unsigned expected
  );
    if (actual != expected) begin
      $display("TEST_RESULT: FAIL: %s expected=%0d actual=%0d",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned i;
    int unsigned p;
    int unsigned watchdog;

    failures = 0;
    for (i = 0; i < DEPTH_WORDS; i++) memory[i] = 16'h0300;
    memory[PIXT_ADDR >> LOCAL_WORD_ADDR_LSB] = 16'hDEAD;
    memory[FILL_ADDR0 >> LOCAL_WORD_ADDR_LSB] = 16'h1111;
    memory[FILL_ADDR1 >> LOCAL_WORD_ADDR_LSB] = 16'h2222;
    memory[MOVE_ADDR >> LOCAL_WORD_ADDR_LSB] = 16'h0000;
    memory[PARTIAL_ADDR >> LOCAL_WORD_ADDR_LSB] = 16'hB0B0;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd0, 32'h0000_0010);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, {16'h0000, DPYCTL_SRT});
    p = place_store_abs(p, 4'd0, A_DPYCTL);

    p = place_movi_il(p, 4'd1, 32'h0000_55AA);
    p = place_movi_il(p, 4'd2, PIXT_ADDR);
    p = place_word(p, pixt_store_enc(4'd1, 4'd2));
    p = place_word(p, pixt_load_enc(4'd2, 4'd3));

    p = place_movi_il_b(p, 4'd2, FILL_ADDR0);
    p = place_movi_il_b(p, 4'd3, 32'h0000_0020);
    p = place_movi_il_b(p, 4'd7, 32'h0001_0002);
    p = place_movi_il_b(p, 4'd9, 32'h0000_1234);
    p = place_word(p, 16'h0FC0);

    // The guide explicitly requires PSIZE=16 to avoid the insertion read.
    // A partial pixel write therefore exercises one MTR followed by one RTM.
    p = place_movi_il(p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd6, PARTIAL_ADDR);
    p = place_word(p, pixt_store_enc(4'd1, 4'd6));
    p = place_movi_il(p, 4'd0, 32'h0000_0010);
    p = place_store_abs(p, 4'd0, A_PSIZE);

    p = place_movi_il(p, 4'd4, 32'h0000_CAFE);
    p = place_store_abs(p, 4'd4, MOVE_ADDR);
    p = place_load_abs(p, 4'd5, MOVE_ADDR);

    p = place_movi_il(p, 4'd0, 32'h0000_0000);
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_word(p, pixt_store_enc(4'd1, 4'd2));
    p = place_movi_il(p, 4'd14, 32'h0158_FACE);

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    watchdog = 0;
    while ((u_system.u_core.u_regfile.a_regs[14] !== 32'h0158_FACE)
           && (watchdog < 10000)) begin
      @(posedge clk);
      watchdog++;
    end
    #1;

    if (u_system.u_core.u_regfile.a_regs[14] !== 32'h0158_FACE) begin
      $display("TEST_RESULT: FAIL: SRT program did not complete");
      failures++;
    end
    check_count("pixel MTR cycles", mtr_count_q, 2);
    check_count("pixel RTM cycles", rtm_count_q, 4);
    check_count("PIXT RTM at 0x800", pixt_rtm_count_q, 1);
    check_count("FILL RTM at 0x900", fill0_rtm_count_q, 1);
    check_count("FILL RTM at 0x910", fill1_rtm_count_q, 1);
    check_count("partial PIXT insertion MTR", partial_mtr_count_q, 1);
    check_count("partial PIXT insertion RTM", partial_rtm_count_q, 1);
    check_count("ordinary MOVE write while SRT set", move_write_count_q, 1);
    check_count("ordinary MOVE read while SRT set", move_read_count_q, 1);
    check_count("normal PIXT write after SRT clear",
                restored_word_write_count_q, 1);

    if (memory[PIXT_ADDR >> LOCAL_WORD_ADDR_LSB] !== 16'h55AA) begin
      $display("TEST_RESULT: FAIL: cleared-SRT PIXT expected 55aa actual=%04h",
               memory[PIXT_ADDR >> LOCAL_WORD_ADDR_LSB]);
      failures++;
    end
    if ((memory[FILL_ADDR0 >> LOCAL_WORD_ADDR_LSB] !== 16'h1111)
        || (memory[FILL_ADDR1 >> LOCAL_WORD_ADDR_LSB] !== 16'h2222)) begin
      $display("TEST_RESULT: FAIL: RTM cycles incorrectly changed normal memory");
      failures++;
    end
    if (memory[PARTIAL_ADDR >> LOCAL_WORD_ADDR_LSB] !== 16'hB0B0) begin
      $display("TEST_RESULT: FAIL: partial MTR/RTM changed normal memory");
      failures++;
    end
    if ((memory[MOVE_ADDR >> LOCAL_WORD_ADDR_LSB] !== 16'hCAFE)
        || (u_system.u_core.u_regfile.a_regs[5] !== 32'h0000_CAFE)) begin
      $display("TEST_RESULT: FAIL: ordinary MOVE traffic changed under SRT");
      failures++;
    end
    if (u_system.u_core.u_regfile.a_regs[3] !== 32'h0000_0000) begin
      $display("TEST_RESULT: FAIL: MTR PIXT destination expected zero actual=%08h",
               u_system.u_core.u_regfile.a_regs[3]);
      failures++;
    end
    if (!opcode_iaq_seen_q || !immediate_noniaq_seen_q) begin
      $display("TEST_RESULT: FAIL: ordinary instruction IAQ behavior not observed");
      failures++;
    end
    if (pixel_protocol_failures_q != 0) begin
      $display("TEST_RESULT: FAIL: %0d pixel cycle protocol/address failure(s)",
               pixel_protocol_failures_q);
      failures++;
    end
    if (controller_protocol_failures_q != 0) begin
      $display("TEST_RESULT: FAIL: %0d held controller payload failure(s)",
               controller_protocol_failures_q);
      failures++;
    end
    if (illegal_opcode) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (DPYCTL.SRT graphics-only MTR/RTM cycles)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_pixel_srt hard timeout");
    $fatal(1);
  end

endmodule : tb_pixel_srt
