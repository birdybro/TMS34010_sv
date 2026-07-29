// -----------------------------------------------------------------------------
// tb_pin_system.sv
//
// End-to-end core-clock to original-pin regression. A pin-level memory target
// observes the multiplexed row/column address, returns a zero reset vector and
// NOP opcodes on LAD, and verifies that the core boots only after the eight
// automatic reset RAS cycles. IAQ must be low for vector data and high for
// each opcode word.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_pin_system;
  import tms34010_pkg::*;

  localparam logic [ADDR_WIDTH-1:0] RESET_VECTOR_HIGH_ADDR =
      RESET_VECTOR_ADDR + ADDR_WIDTH'(LOCAL_WORD_WIDTH);

  logic core_clk = 1'b0;
  logic bus_clk8x = 1'b0;
  logic rst = 1'b1;

  local_word_t     lad_i;
  local_word_t     lad_o;
  logic            lad_oe;
  logic            lclk1;
  logic            lclk2;
  logic            ras_n;
  logic            lal_n;
  logic            cas_n;
  logic            we_n;
  logic            tr_qe_n;
  logic            den_n;
  logic            ddout;
  local_subphase_t subphase;
  logic            init_done;
  logic            local_busy;
  logic            bridge_busy;
  core_state_t     core_state;
  logic [ADDR_WIDTH-1:0] pc;
  instr_word_t     instr_word;
  logic            illegal_opcode;

  integer errors = 0;
  integer init_ras_count = 0;
  integer word_cycle_count = 0;
  integer reset_word_count = 0;
  integer opcode_word_count = 0;
  logic   previous_ras_n = 1'b1;
  logic   row_valid_q = 1'b0;
  local_word_t row_q = '0;
  local_word_t read_data_q = '0;
  logic   saw_bridge_busy = 1'b0;
  logic   saw_first_opcode_iaq = 1'b0;

  always #8 core_clk = ~core_clk;
  always #1 bus_clk8x = ~bus_clk8x;

  assign lad_i = read_data_q;

  tms34010_pin_system dut (
    .core_clk_i        (core_clk),
    .bus_clk8x_i       (bus_clk8x),
    .rst               (rst),
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
    .lrdy_i            (1'b1),
    .lad_i             (lad_i),
    .lad_o             (lad_o),
    .lad_oe_o          (lad_oe),
    .lclk1_o           (lclk1),
    .lclk2_o           (lclk2),
    .ras_n_o           (ras_n),
    .lal_n_o           (lal_n),
    .cas_n_o           (cas_n),
    .we_n_o            (we_n),
    .tr_qe_n_o         (tr_qe_n),
    .den_n_o           (den_n),
    .ddout_o           (ddout),
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
        $display("CHECK_FAIL: %s at t=%0t phase=%0d",
                 message, $time, subphase);
        errors = errors + 1;
      end
    end
  endtask

  // Decode each ordinary word's physical row/column pair. First-period LAL is
  // still high at Q3B/Q4A, which distinguishes it from the second data period.
  always @(negedge bus_clk8x) begin
    logic [29:0] physical_bit_address;

    if (rst) begin
      init_ras_count = 0;
      previous_ras_n = 1'b1;
      row_valid_q    = 1'b0;
      read_data_q    = '0;
    end else begin
      if (bridge_busy)
        saw_bridge_busy = 1'b1;

      if (!init_done && previous_ras_n && !ras_n) begin
        init_ras_count = init_ras_count + 1;
        check(subphase == LOCAL_PHASE_Q3B,
              "automatic reset RAS must begin in Q3B");
        check(lad_oe && (lad_o == 16'h0000),
              "automatic reset row/status must be zero");
        check(lal_n && cas_n && we_n && tr_qe_n && den_n && ddout,
              "automatic reset cycle must be RAS-only");
      end
      previous_ras_n = ras_n;

      if (init_done && (subphase == LOCAL_PHASE_Q3B)
          && !ras_n && lal_n && lad_oe) begin
        row_q      = lad_o;
        row_valid_q = 1'b1;
      end

      if (init_done && row_valid_q
          && (subphase == LOCAL_PHASE_Q4A)
          && lal_n && lad_oe && row_q[15] && lad_o[14]) begin
        physical_bit_address = '0;
        physical_bit_address[29:27] = lad_o[13:11];
        physical_bit_address[26:12] = row_q[14:0];
        physical_bit_address[14:4]  = lad_o[10:0];

        word_cycle_count = word_cycle_count + 1;

        if ((physical_bit_address[29:4]
            == RESET_VECTOR_ADDR[29:4])
            || (physical_bit_address[29:4]
                == RESET_VECTOR_HIGH_ADDR[29:4])) begin
          reset_word_count = reset_word_count + 1;
          check(!lad_o[15], "reset-vector word must drive IAQ low");
          read_data_q = 16'h0000;
        end else begin
          opcode_word_count = opcode_word_count + 1;
          check(lad_o[15], "opcode word must drive IAQ high");
          if (physical_bit_address[29:4] == 26'h0000000)
            saw_first_opcode_iaq = lad_o[15];
          read_data_q = 16'h0300;
        end

        row_valid_q = 1'b0;
      end
    end
  end

  initial begin
    repeat (6) @(posedge core_clk);
    @(negedge core_clk);
    rst = 1'b0;

    wait (pc >= 32'd48);
    repeat (3) @(posedge core_clk);

    check(init_done, "local-bus reset initialization did not complete");
    check(init_ras_count == 8,
          "integrated controller must issue exactly eight reset RAS cycles");
    check(reset_word_count == 2,
          "32-bit reset vector must use exactly two physical words");
    check(opcode_word_count >= 3,
          "core did not execute three physical opcode fetches");
    check(word_cycle_count >= 5,
          "expected reset-vector and opcode word traffic");
    check(saw_first_opcode_iaq,
          "first opcode fetch at address zero did not carry IAQ");
    check(saw_bridge_busy, "integrated CDC bridge never accepted a command");
    check(instr_word == 16'h0300, "pin-supplied NOP was not fetched");
    check(!illegal_opcode, "pin-level NOP stream raised illegal opcode");
    check(local_busy || (core_state != CORE_RESET),
          "integrated system did not leave architectural reset");

    if (errors == 0) begin
      $display("TEST_RESULT: PASS");
    end else begin
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    end
    $finish;
  end

  initial begin
    #50000;
    $display("TEST_RESULT: FAIL (timeout)");
    $finish;
  end

endmodule : tb_pin_system

`default_nettype wire
