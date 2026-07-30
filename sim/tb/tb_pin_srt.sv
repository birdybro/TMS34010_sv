// -----------------------------------------------------------------------------
// tb_pin_srt.sv
//
// Full processor-to-package-pin DPYCTL.SRT regression. A program fetched
// through the original multiplexed local bus emits a direct PIXT RTM, a PIXT
// MTR, and a partial-field PIXT MTR/RTM pair. The test checks the exact
// transfer order and the documented row, column, TR/QE, W, RAS, CAS, LAL,
// IAQ, and second-period LAD phases after both CDC crossings.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_pin_srt;
  import tms34010_pkg::*;

  localparam int unsigned DEPTH_WORDS = 256;
  localparam logic [ADDR_WIDTH-1:0] RESET_VECTOR_HIGH_ADDR =
      RESET_VECTOR_ADDR + ADDR_WIDTH'(LOCAL_WORD_WIDTH);
  localparam logic [ADDR_WIDTH-1:0] A_PSIZE =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PSIZE) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [ADDR_WIDTH-1:0] DIRECT_ADDR = 32'h0000_0800;
  localparam logic [ADDR_WIDTH-1:0] PARTIAL_ADDR = 32'h0000_0908;
  localparam logic [ADDR_WIDTH-1:0] PARTIAL_WORD_ADDR = 32'h0000_0900;
  localparam logic [15:0] DPYCTL_SRT =
      16'h0001 << DPYCTL_SRT_BIT;
  localparam logic [31:0] DONE_MARKER = 32'h0171_FACE;

  logic core_clk = 1'b0;
  logic bus_clk8x = 1'b0;
  logic vclk = 1'b0;
  logic rst = 1'b1;

  local_word_t     lad_i;
  local_word_t     lad_o;
  logic            lad_oe;
  logic            ras_n;
  logic            lal_n;
  logic            cas_n;
  logic            we_n;
  logic            tr_qe_n;
  logic            den_n;
  logic            ddout;
  logic            hlda_emua_n;
  logic            hcs_n = 1'b0;
  local_subphase_t subphase;
  logic            init_done;
  logic            local_busy;
  logic            bridge_busy;
  core_state_t     core_state;
  logic [ADDR_WIDTH-1:0] pc;
  instr_word_t     instr_word;
  logic            illegal_opcode;

  local_word_t memory [0:DEPTH_WORDS-1];
  local_word_t read_data_q = '0;
  local_word_t row_q = '0;
  logic row_valid_q = 1'b0;
  logic transfer_open_q = 1'b0;
  logic previous_ras_n_q = 1'b1;
  integer transfer_count_q = 0;
  integer transfer_phase_count_q = 0;
  integer ordinary_word_count_q = 0;
  integer io_cycle_count_q = 0;
  integer errors = 0;

  always #7 core_clk = ~core_clk;
  always #1 bus_clk8x = ~bus_clk8x;
  always #5 vclk = ~vclk;

  assign lad_i = read_data_q;

  tms34010_pin_system dut (
    .core_clk_i        (core_clk),
    .bus_clk8x_i       (bus_clk8x),
    .vclk_i            (vclk),
    .core_rst_i        (rst),
    .bus_rst_i         (rst),
    .video_rst_i       (rst),
    .video_hsync_n_i   (1'b1),
    .video_vsync_n_i   (1'b1),
    .run_emu_n_i       (1'b1),
    .hcs_n_i           (hcs_n),
    .hread_n_i         (1'b1),
    .hwrite_n_i        (1'b1),
    .hlds_n_i          (1'b1),
    .huds_n_i          (1'b1),
    .hfs_i             (HOST_REG_HSTADRL),
    .hd_i              (16'h0000),
    .hd_o              (),
    .hd_oe_o           (),
    .hrdy_o            (),
    .hint_n_o          (),
    .lint1_n_i         (1'b1),
    .lint2_n_i         (1'b1),
    .dpyint_set_i      (1'b0),
    .hold_n_i          (1'b1),
    .hlda_emua_n_o     (hlda_emua_n),
    .video_hsync_o     (),
    .video_vsync_o     (),
    .video_hblank_o    (),
    .video_vblank_o    (),
    .video_blank_o     (),
    .video_hsync_oe_o  (),
    .video_vsync_oe_o  (),
    .lrdy_i            (1'b1),
    .lad_i             (lad_i),
    .lad_o             (lad_o),
    .lad_oe_o          (lad_oe),
    .lclk1_o           (),
    .lclk2_o           (),
    .ras_n_o           (ras_n),
    .lal_n_o           (lal_n),
    .cas_n_o           (cas_n),
    .we_n_o            (we_n),
    .tr_qe_n_o         (tr_qe_n),
    .den_n_o           (den_n),
    .ddout_o           (ddout),
    .ras_oe_o          (),
    .lal_oe_o          (),
    .cas_oe_o          (),
    .we_oe_o           (),
    .tr_qe_oe_o        (),
    .den_oe_o          (),
    .ddout_oe_o        (),
    .subphase_o        (subphase),
    .local_init_done_o (init_done),
    .local_cycle_busy_o(local_busy),
    .bridge_busy_o     (bridge_busy),
    .state_o           (core_state),
    .pc_o              (pc),
    .instr_word_o      (instr_word),
    .illegal_opcode_o  (illegal_opcode)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s at t=%0t phase=%0d kind=%0d addr=%08h",
                 message, $time, subphase, dut.local_command.kind,
                 dut.local_command.addr);
        errors = errors + 1;
      end
    end
  endtask

  function automatic local_cycle_kind_t expected_kind(input integer index);
    unique case (index)
      0: expected_kind = LOCAL_CYCLE_PIXEL_RTM;
      1: expected_kind = LOCAL_CYCLE_PIXEL_MTR;
      2: expected_kind = LOCAL_CYCLE_PIXEL_MTR;
      3: expected_kind = LOCAL_CYCLE_PIXEL_RTM;
      default: expected_kind = LOCAL_CYCLE_WORD_READ;
    endcase
  endfunction

  function automatic logic [ADDR_WIDTH-1:0] expected_addr(
    input integer index
  );
    unique case (index)
      0, 1: expected_addr = DIRECT_ADDR;
      2, 3: expected_addr = PARTIAL_WORD_ADDR;
      default: expected_addr = '0;
    endcase
  endfunction

  function automatic local_word_t expected_row(
    input logic [ADDR_WIDTH-1:0] address
  );
    expected_row = {1'b1, address[26:12]};
  endfunction

  function automatic local_word_t expected_transfer_column(
    input logic [ADDR_WIDTH-1:0] address
  );
    local_word_t result;
    begin
      result = {1'b0, 1'b1, address[29:27], address[14:4]};
      result[14] = 1'b0;
      expected_transfer_column = result;
    end
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
    memory[p]     = 16'h09E0 | instr_word_t'(idx);
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

  // Reconstruct ordinary word cycles for the boot vector and program. Pixel
  // transfers deliberately have column TR low, so they cannot be mistaken
  // for instruction/data traffic by this pin-level target.
  always @(negedge bus_clk8x) begin : pin_monitor
    logic [29:0] physical_bit_address;
    local_cycle_kind_t active_kind;
    logic [ADDR_WIDTH-1:0] active_addr;

    if (rst) begin
      read_data_q = '0;
      row_q = '0;
      row_valid_q = 1'b0;
      transfer_open_q = 1'b0;
      previous_ras_n_q = 1'b1;
      transfer_count_q = 0;
      transfer_phase_count_q = 0;
      ordinary_word_count_q = 0;
      io_cycle_count_q = 0;
    end else begin
      if (init_done && previous_ras_n_q && !ras_n) begin
        active_kind = dut.local_command.kind;
        active_addr = dut.local_command.addr;
        if ((active_kind == LOCAL_CYCLE_PIXEL_MTR)
            || (active_kind == LOCAL_CYCLE_PIXEL_RTM)) begin
          check(subphase == LOCAL_PHASE_Q3B,
                "pixel transfer RAS did not fall in Q3B");
          check(transfer_count_q < 4,
                "unexpected extra pixel transfer");
          if (transfer_count_q < 4) begin
            check(active_kind == expected_kind(transfer_count_q),
                  "pixel transfer kind/order mismatch");
            check(active_addr == expected_addr(transfer_count_q),
                  "pixel transfer aligned address/order mismatch");
          end
          check(lad_oe && (lad_o == expected_row(active_addr)),
                "pixel transfer row address/status mismatch");
          check(lal_n && cas_n && !tr_qe_n && den_n && ddout,
                "pixel transfer row control mismatch");
          check(we_n == (active_kind == LOCAL_CYCLE_PIXEL_MTR),
                "MTR/RTM W level at RAS fall mismatch");
          check(!dut.local_command.iaq,
                "pixel transfer retained instruction-acquisition status");
          transfer_open_q = 1'b1;
          transfer_count_q = transfer_count_q + 1;
          transfer_phase_count_q = transfer_phase_count_q + 1;
          row_valid_q = 1'b0;
        end else begin
          check(tr_qe_n,
                "non-pixel transfer asserted TR/QE at RAS fall");
          if ((active_kind == LOCAL_CYCLE_WORD_READ)
              || (active_kind == LOCAL_CYCLE_WORD_WRITE)) begin
            row_q = lad_o;
            row_valid_q = 1'b1;
          end
        end
      end
      previous_ras_n_q = ras_n;

      if (transfer_open_q && (subphase == LOCAL_PHASE_Q4A)) begin
        check(!ras_n && lal_n && cas_n && we_n && !tr_qe_n,
              "pixel transfer column controls mismatch");
        check(lad_oe
              && (lad_o == expected_transfer_column(
                    dut.local_command.addr)),
              "pixel transfer column address/status mismatch");
        transfer_phase_count_q = transfer_phase_count_q + 1;
      end

      if (transfer_open_q && (subphase == LOCAL_PHASE_Q1B)) begin
        check(!ras_n && !lal_n && !cas_n && we_n && !tr_qe_n,
              "pixel transfer second-period Q1B controls mismatch");
        check(lad_oe && (lad_o == 16'h0000),
              "pixel transfer incorrectly exchanged LAD data");
        transfer_phase_count_q = transfer_phase_count_q + 1;
      end

      if (transfer_open_q && (subphase == LOCAL_PHASE_Q3A)) begin
        check(!ras_n && !lal_n && !cas_n && we_n && tr_qe_n,
              "pixel transfer did not release TR/QE before completion");
        check(lad_oe && (lad_o == 16'h0000),
              "pixel transfer second period did not retain zero LAD");
        transfer_phase_count_q = transfer_phase_count_q + 1;
        transfer_open_q = 1'b0;
      end

      if (init_done && row_valid_q
          && (subphase == LOCAL_PHASE_Q4A)
          && lal_n && lad_oe && row_q[15] && lad_o[14]) begin
        physical_bit_address = '0;
        physical_bit_address[29:27] = lad_o[13:11];
        physical_bit_address[26:12] = row_q[14:0];
        physical_bit_address[14:4] = lad_o[10:0];

        ordinary_word_count_q = ordinary_word_count_q + 1;
        if ((physical_bit_address[29:4]
             == RESET_VECTOR_ADDR[29:4])
            || (physical_bit_address[29:4]
                == RESET_VECTOR_HIGH_ADDR[29:4])) begin
          read_data_q = 16'h0000;
        end else if (int'(physical_bit_address[29:4]) < DEPTH_WORDS) begin
          read_data_q = memory[physical_bit_address[11:4]];
        end else begin
          read_data_q = 16'h0300;
        end
        row_valid_q = 1'b0;
      end

      if (init_done && !transfer_open_q
          && (subphase == LOCAL_PHASE_Q4A)
          && lal_n && lad_oe
          && (dut.local_command.kind == LOCAL_CYCLE_IO_WRITE)) begin
        check((lad_o == 16'h4000) && tr_qe_n && we_n,
              "on-chip I/O traffic changed class while SRT enabled");
        io_cycle_count_q = io_cycle_count_q + 1;
        row_valid_q = 1'b0;
      end
    end
  end

  initial begin : main
    int unsigned i;
    int unsigned p;
    int unsigned watchdog;

    for (i = 0; i < DEPTH_WORDS; i++) memory[i] = 16'h0300;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il(p, 4'd0, 32'h0000_0010);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd0, {16'h0000, DPYCTL_SRT});
    p = place_store_abs(p, 4'd0, A_DPYCTL);
    p = place_movi_il(p, 4'd1, 32'h0000_55AA);
    p = place_movi_il(p, 4'd2, DIRECT_ADDR);
    p = place_word(p, pixt_store_enc(4'd1, 4'd2));
    p = place_word(p, pixt_load_enc(4'd2, 4'd3));
    p = place_movi_il(p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il(p, 4'd6, PARTIAL_ADDR);
    p = place_word(p, pixt_store_enc(4'd1, 4'd6));
    p = place_movi_il(p, 4'd14, DONE_MARKER);

    repeat (6) @(posedge core_clk);
    @(negedge core_clk);
    rst = 1'b0;
    hcs_n = 1'b1;

    watchdog = 0;
    while ((dut.u_system.u_core.u_regfile.a_regs[14] !== DONE_MARKER)
           && (watchdog < 20000)) begin
      @(posedge core_clk);
      watchdog++;
    end
    repeat (6) @(posedge core_clk);
    #1;

    check(dut.u_system.u_core.u_regfile.a_regs[14] == DONE_MARKER,
          "pin-level SRT program did not complete");
    check(dut.u_system.u_core.u_regfile.a_regs[3] == 32'h0000_0000,
          "MTR read did not return deterministic zero");
    check(transfer_count_q == 4,
          "pixel program did not emit exactly four physical transfers");
    check(transfer_phase_count_q == 16,
          "not every physical transfer phase was observed exactly once");
    check(ordinary_word_count_q > 20,
          "program instruction/immediate traffic was not observed");
    check(io_cycle_count_q == 3,
          "PSIZE/DPYCTL writes did not remain three ordinary I/O cycles");
    check(init_done && !illegal_opcode,
          "integrated processor failed initialization or decoded illegally");
    check(hlda_emua_n && (core_state != CORE_RESET)
          && local_busy == bridge_busy,
          "integrated pin system ended in an incoherent state");

    if (errors == 0)
      $display("TEST_RESULT: PASS (full-pin SRT MTR/RTM sequence and phases)");
    else
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL (tb_pin_srt timeout)");
    $fatal(1);
  end

endmodule : tb_pin_srt

`default_nettype wire
