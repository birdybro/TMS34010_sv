// -----------------------------------------------------------------------------
// tb_pin_system.sv
//
// End-to-end core-clock to original-pin regression. A pin-level memory target
// observes the multiplexed row/column address, returns a boot program on LAD,
// and verifies that the core boots only after the eight automatic reset RAS
// cycles. The program and asynchronous original-pin host bus both write/read
// PMASK through physical I/O cycles, while IAQ distinguishes opcode words
// from vector/immediate data.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_pin_system;
  import tms34010_pkg::*;

  localparam logic [ADDR_WIDTH-1:0] RESET_VECTOR_HIGH_ADDR =
      RESET_VECTOR_ADDR + ADDR_WIDTH'(LOCAL_WORD_WIDTH);
  localparam logic [ADDR_WIDTH-1:0] PMASK_ADDR =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PMASK) << 4);

  logic core_clk = 1'b0;
  logic bus_clk8x = 1'b0;
  logic vclk = 1'b0;
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
  logic            ras_oe;
  logic            lal_oe;
  logic            cas_oe;
  logic            we_oe;
  logic            tr_qe_oe;
  logic            den_oe;
  logic            ddout_oe;
  logic            run_emu_n = 1'b1;
  logic            hold_n = 1'b1;
  logic            hlda_emua_n;
  logic            hcs_n = 1'b0;
  logic            hread_n = 1'b1;
  logic            hwrite_n = 1'b1;
  logic            hlds_n = 1'b1;
  logic            huds_n = 1'b1;
  logic [1:0]      hfs = HOST_REG_HSTADRL;
  local_word_t     hd_i = '0;
  local_word_t     hd_o;
  logic [1:0]      hd_oe;
  logic            hrdy;
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
  integer immediate_word_count = 0;
  integer io_address_count = 0;
  logic   previous_ras_n = 1'b1;
  logic   row_valid_q = 1'b0;
  local_word_t row_q = '0;
  local_word_t read_data_q = '0;
  logic   saw_bridge_busy = 1'b0;
  logic   saw_first_opcode_iaq = 1'b0;
  logic   io_cycle_pending = 1'b0;
  local_cycle_kind_t io_kind_q = LOCAL_CYCLE_WORD_READ;
  logic   saw_io_address = 1'b0;
  integer io_write_address_count = 0;
  integer io_read_address_count = 0;
  logic   saw_cpu_io_write_data = 1'b0;
  logic   saw_host_io_write_data = 1'b0;
  logic   saw_io_read_data_phase = 1'b0;
  logic   emu_halt_arm = 1'b0;
  logic   emu_halt_injected = 1'b0;

  always #8 core_clk = ~core_clk;
  always #1 bus_clk8x = ~bus_clk8x;
  always #3 vclk = ~vclk;

  assign lad_i = read_data_q;

  tms34010_pin_system dut (
    .core_clk_i        (core_clk),
    .bus_clk8x_i       (bus_clk8x),
    .vclk_i            (vclk),
    .rst               (rst),
    .video_hsync_n_i   (1'b1),
    .video_vsync_n_i   (1'b1),
    .run_emu_n_i       (run_emu_n),
    .hcs_n_i           (hcs_n),
    .hread_n_i         (hread_n),
    .hwrite_n_i        (hwrite_n),
    .hlds_n_i          (hlds_n),
    .huds_n_i          (huds_n),
    .hfs_i             (hfs),
    .hd_i              (hd_i),
    .hd_o              (hd_o),
    .hd_oe_o           (hd_oe),
    .hrdy_o            (hrdy),
    .hint_n_o          (),
    .lint1_n_i         (1'b1),
    .lint2_n_i         (1'b1),
    .dpyint_set_i      (1'b0),
    .hold_n_i          (hold_n),
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
    .lclk1_o           (lclk1),
    .lclk2_o           (lclk2),
    .ras_n_o           (ras_n),
    .lal_n_o           (lal_n),
    .cas_n_o           (cas_n),
    .we_n_o            (we_n),
    .tr_qe_n_o         (tr_qe_n),
    .den_n_o           (den_n),
    .ddout_o           (ddout),
    .ras_oe_o          (ras_oe),
    .lal_oe_o          (lal_oe),
    .cas_oe_o          (cas_oe),
    .we_oe_o           (we_oe),
    .tr_qe_oe_o        (tr_qe_oe),
    .den_oe_o          (den_oe),
    .ddout_oe_o        (ddout_oe),
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

  function automatic local_word_t program_word(
    input logic [29:0] physical_bit_address
  );
    logic [ADDR_WIDTH-1:0] address;
    begin
      address = {{(ADDR_WIDTH-30){1'b0}}, physical_bit_address};
      unique case (address)
        32'h0000_0000: program_word = 16'h09E0; // MOVI IL BEEF,A0
        32'h0000_0010: program_word = 16'hBEEF;
        32'h0000_0020: program_word = 16'h0000;
        32'h0000_0030: program_word = 16'h0580; // MOVE A0,@PMASK
        32'h0000_0040: program_word = PMASK_ADDR[15:0];
        32'h0000_0050: program_word = PMASK_ADDR[31:16];
        32'h0000_0060: program_word = 16'h05A1; // MOVE @PMASK,A1
        32'h0000_0070: program_word = PMASK_ADDR[15:0];
        32'h0000_0080: program_word = PMASK_ADDR[31:16];
        32'h0000_0090: program_word = 16'h0100; // EMU in RUN state
        default:       program_word = 16'h0300; // NOP
      endcase
    end
  endfunction

  // Decode each ordinary word's physical row/column pair. First-period LAL is
  // still high at Q3B/Q4A, which distinguishes it from the second data period.
  always @(negedge bus_clk8x) begin
    logic [29:0] physical_bit_address;

    if (rst) begin
      init_ras_count = 0;
      previous_ras_n = 1'b1;
      row_valid_q    = 1'b0;
      read_data_q    = '0;
      io_cycle_pending = 1'b0;
      io_kind_q = LOCAL_CYCLE_WORD_READ;
      io_address_count = 0;
      io_write_address_count = 0;
      io_read_address_count = 0;
      emu_halt_injected = 1'b0;
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

        if ((row_q == 16'h8000) && (lad_o == 16'h4000)) begin
          // I/O row/column/status are all zero apart from inactive RF. The
          // write must not update the on-chip register until this physical
          // cycle has completed and its acknowledge returns to the core.
          saw_io_address = 1'b1;
          io_address_count = io_address_count + 1;
          io_cycle_pending = 1'b1;
          io_kind_q = dut.local_command.kind;
          if (dut.local_command.kind == LOCAL_CYCLE_IO_WRITE) begin
            io_write_address_count = io_write_address_count + 1;
            if (io_write_address_count == 1)
              check(dut.u_system.u_core.u_io_regs.io_reg[IO_IDX_PMASK]
                    == 16'h0000,
                    "PMASK changed before processor I/O completion");
            else if (io_write_address_count == 2)
              check(dut.u_system.u_core.u_io_regs.io_reg[IO_IDX_PMASK]
                    == 16'hBEEF,
                    "PMASK changed before host I/O completion");
          end else if (dut.local_command.kind == LOCAL_CYCLE_IO_READ) begin
            io_read_address_count = io_read_address_count + 1;
          end else begin
            check(1'b0, "I/O address phase used a non-I/O cycle kind");
          end
        end else begin
          word_cycle_count = word_cycle_count + 1;

          if ((physical_bit_address[29:4]
             == RESET_VECTOR_ADDR[29:4])
              || (physical_bit_address[29:4]
                  == RESET_VECTOR_HIGH_ADDR[29:4])) begin
            reset_word_count = reset_word_count + 1;
            check(!lad_o[15], "reset-vector word must drive IAQ low");
            read_data_q = 16'h0000;
          end else begin
            if (lad_o[15]) begin
              opcode_word_count = opcode_word_count + 1;
            end else begin
              immediate_word_count = immediate_word_count + 1;
            end
            if (physical_bit_address[29:4] == 26'h0000000)
              saw_first_opcode_iaq = lad_o[15];
            if ((physical_bit_address[29:4] == 26'h0000001)
                || (physical_bit_address[29:4] == 26'h0000002)
                || (physical_bit_address[29:4] == 26'h0000004)
                || (physical_bit_address[29:4] == 26'h0000005)
                || (physical_bit_address[29:4] == 26'h0000007)
                || (physical_bit_address[29:4] == 26'h0000008))
              check(!lad_o[15],
                    "MOVI/MOVE absolute extension word must drive IAQ low");
            if (lad_o[15] && emu_halt_arm && !emu_halt_injected) begin
              read_data_q = 16'h0100;
              emu_halt_injected = 1'b1;
            end else begin
              read_data_q = program_word(physical_bit_address);
            end
          end
        end

        row_valid_q = 1'b0;
      end

      if (io_cycle_pending && (subphase == LOCAL_PHASE_Q2A)
          && !ras_n && !lal_n && cas_n) begin
        if (io_kind_q == LOCAL_CYCLE_IO_WRITE) begin
          check(lad_oe,
                "I/O write data phase must drive LAD");
          if (io_write_address_count == 1) begin
            check(lad_o == 16'hBEEF,
                  "processor I/O write data must expose BEEF");
            saw_cpu_io_write_data = 1'b1;
          end else if (io_write_address_count == 2) begin
            check(lad_o == 16'h1234,
                  "host I/O write data must expose 1234");
            saw_host_io_write_data = 1'b1;
          end
        end else begin
          check(io_kind_q == LOCAL_CYCLE_IO_READ,
                "I/O data phase kind must be read or write");
          check(!lad_oe,
                "I/O read data phase must release LAD");
          saw_io_read_data_phase = 1'b1;
        end
        check(we_n && tr_qe_n && den_n && ddout,
              "I/O cycle must leave non-RAS/LAL controls inactive");
        io_cycle_pending = 1'b0;
      end
    end
  end

  task automatic host_cycle(
    input  logic          write_access,
    input  host_reg_sel_t selected_reg,
    input  logic [1:0]    byte_enable,
    input  local_word_t   write_data,
    output local_word_t   read_data
  );
    int unsigned watchdog;
    begin
      @(negedge core_clk);
      hfs      = selected_reg;
      hd_i     = write_data;
      hread_n  = write_access;
      hwrite_n = !write_access;
      hlds_n   = !byte_enable[0];
      huds_n   = !byte_enable[1];
      #2;
      hcs_n = 1'b0;
      #1;
      check(!hrdy, "physical host access did not lower HRDY");
      check(hd_oe == 2'b00, "physical HD drove before host completion");

      watchdog = 0;
      while (!hrdy && (watchdog < 100)) begin
        @(posedge core_clk);
        #1;
        watchdog++;
      end
      check(hrdy, "pin-system physical host cycle timed out");
      read_data = hd_o;
      if (write_access)
        check(hd_oe == 2'b00, "physical host write drove HD");
      else
        check(hd_oe == byte_enable,
              "physical host read enabled the wrong HD lanes");

      @(negedge core_clk);
      hcs_n    = 1'b1;
      hread_n  = 1'b1;
      hwrite_n = 1'b1;
      hlds_n   = 1'b1;
      huds_n   = 1'b1;
      hd_i     = '0;
      #1;
      check(hrdy, "HRDY remained low after physical HCS release");
      check(hd_oe == 2'b00, "HD drove after physical HCS release");
      repeat (3) @(posedge core_clk);
      #1;
    end
  endtask

  task automatic host_write(
    input host_reg_sel_t selected_reg,
    input logic [1:0]    byte_enable,
    input local_word_t   write_data
  );
    local_word_t ignored;
    host_cycle(1'b1, selected_reg, byte_enable, write_data, ignored);
  endtask

  task automatic host_read(
    input  host_reg_sel_t selected_reg,
    output local_word_t   read_data
  );
    host_cycle(1'b0, selected_reg, 2'b11, 16'h0000, read_data);
  endtask

  task automatic wait_host_idle;
    int unsigned watchdog;
    begin
      watchdog = 0;
      while (dut.core_host_busy && (watchdog < 200)) begin
        @(posedge core_clk);
        #1;
        watchdog++;
      end
      check(!dut.core_host_busy,
            "pin-system host-indirect cycle timed out");
    end
  endtask

  task automatic wait_bus_phase(input local_subphase_t wanted);
    begin
      @(negedge bus_clk8x);
      while (subphase != wanted)
        @(negedge bus_clk8x);
    end
  endtask

  task automatic check_majority_oe(
    input logic expected,
    input string label
  );
    begin
      check(ras_oe == expected, {label, " RAS OE"});
      check(lal_oe == expected, {label, " LAL OE"});
      check(cas_oe == expected, {label, " CAS OE"});
      check(we_oe == expected, {label, " W OE"});
      check(tr_qe_oe == expected, {label, " TR/QE OE"});
      if (!expected)
        check(!lad_oe, {label, " LAD OE"});
    end
  endtask

  task automatic check_slow_oe(
    input logic expected,
    input string label
  );
    begin
      check(den_oe == expected, {label, " DEN OE"});
      check(ddout_oe == expected, {label, " DDOUT OE"});
    end
  endtask

  task automatic check_emu_window(input string label);
    int unsigned watchdog;
    begin
      watchdog = 0;
      while (!((subphase == LOCAL_PHASE_Q1A) && !hlda_emua_n)
             && (watchdog < 5000)) begin
        @(negedge bus_clk8x);
        watchdog++;
      end
      check(watchdog < 5000, {label, " EMUA window timed out"});
      check(subphase == LOCAL_PHASE_Q1A,
            {label, " EMUA did not start in Q1A"});
      check(!hlda_emua_n, {label, " EMUA inactive in Q1A"});
      wait_bus_phase(LOCAL_PHASE_Q1B);
      check(!hlda_emua_n, {label, " EMUA inactive in Q1B"});
      wait_bus_phase(LOCAL_PHASE_Q2A);
      check(!hlda_emua_n, {label, " EMUA inactive in Q2A"});
      wait_bus_phase(LOCAL_PHASE_Q2B);
      check(!hlda_emua_n, {label, " EMUA inactive in Q2B"});
      wait_bus_phase(LOCAL_PHASE_Q3A);
      check(hlda_emua_n, {label, " EMUA leaked into Q3/Q4"});
    end
  endtask

  initial begin
    local_word_t rd;
    logic [ADDR_WIDTH-1:0] held_pc;
    int unsigned watchdog;

    repeat (6) @(posedge core_clk);
    @(negedge core_clk);
    rst = 1'b0;
    // HCS was active throughout reset to select self-bootstrap/run. Release
    // it once the strap has been sampled so later host cycles can use HCS as
    // the last-active/first-inactive physical access strobe.
    hcs_n = 1'b1;

    // The fixed EMU at address 0090h executes in RUN mode. Its core-clock
    // event must become one and only one complete Q1/Q2 pulse on the shared
    // physical output.
    check_emu_window("RUN-mode");
    wait_bus_phase(LOCAL_PHASE_Q1A);
    check(hlda_emua_n, "RUN-mode EMUA repeated without another opcode");

    wait (pc >= 32'd160);
    repeat (3) @(posedge core_clk);

    check(init_done, "local-bus reset initialization did not complete");
    check(init_ras_count == 8,
          "integrated controller must issue exactly eight reset RAS cycles");
    check(reset_word_count == 2,
          "32-bit reset vector must use exactly two physical words");
    check(opcode_word_count >= 3,
          "core did not execute three physical opcode fetches");
    check(immediate_word_count >= 6,
          "instruction extension words did not carry data status");
    check(word_cycle_count >= 12,
          "expected reset-vector and program word traffic");
    check(saw_first_opcode_iaq,
          "first opcode fetch at address zero did not carry IAQ");
    check(saw_bridge_busy, "integrated CDC bridge never accepted a command");
    check(saw_io_address, "processor write did not emit an I/O address cycle");
    check(io_address_count == 2,
          "processor I/O write/read must each emit one physical cycle");
    check(io_write_address_count == 1,
          "processor must emit exactly one I/O write cycle");
    check(io_read_address_count == 1,
          "processor must emit exactly one I/O read cycle");
    check(saw_cpu_io_write_data,
          "processor I/O write data was not driven on LAD");
    check(saw_io_read_data_phase,
          "processor I/O read did not release LAD during its data phase");
    check(dut.u_system.u_core.u_io_regs.io_reg[IO_IDX_PMASK] == 16'hBEEF,
          "processor I/O write did not commit PMASK exactly once");
    check(dut.u_system.u_core.u_regfile.a_regs[1] == 32'h0000_BEEF,
          "processor I/O read did not return on-chip PMASK data");

    // A host address completion and HSTDATA read must now use the same
    // RAS/LAL-only physical I/O read path. The following HSTDATA write must
    // drive 1234 on LAD and update PMASK only after the response crosses back.
    host_write(HOST_REG_HSTADRL, 2'b11, PMASK_ADDR[15:0]);
    host_write(HOST_REG_HSTADRH, 2'b11, PMASK_ADDR[31:16]);
    wait_host_idle();
    host_read(HOST_REG_HSTDATA, rd);
    check(rd == 16'hBEEF,
          "host-indirect PMASK read did not return BEEF");
    wait_host_idle();
    host_write(HOST_REG_HSTDATA, 2'b11, 16'h1234);
    check(dut.u_system.u_core.u_io_regs.io_reg[IO_IDX_PMASK] == 16'hBEEF,
          "host-indirect PMASK write committed before physical completion");
    wait_host_idle();
    repeat (3) @(posedge core_clk);

    check(io_address_count == 5,
          "processor and host I/O operations must emit five physical cycles");
    check(io_write_address_count == 2,
          "processor and host must emit two physical I/O writes");
    check(io_read_address_count == 3,
          "processor and host must emit three physical I/O reads");
    check(saw_host_io_write_data,
          "host-indirect I/O write data was not driven on LAD");
    check(dut.u_system.u_core.u_io_regs.io_reg[IO_IDX_PMASK] == 16'h1234,
          "host-indirect I/O write did not commit PMASK on completion");

    // Assert the physical active-low HOLD during live NOP traffic. The
    // current cycle must retire before the first Q3/Q4 early HLDA; the bus
    // then releases majority outputs at Q2 and DEN/DDOUT at Q3.
    do begin
      wait_bus_phase(LOCAL_PHASE_Q1A);
    end while (!local_busy || !bridge_busy);
    hold_n = 1'b0;
    wait_bus_phase(LOCAL_PHASE_Q2A);
    check(hlda_emua_n, "HLDA asserted on the HOLD sample edge");

    watchdog = 0;
    while (hlda_emua_n && (watchdog < 400)) begin
      @(negedge bus_clk8x);
      watchdog++;
    end
    check(!hlda_emua_n, "physical HOLD did not produce early HLDA");
    check(subphase == LOCAL_PHASE_Q3A,
          "first HLDA assertion must begin in Q3");
    check_majority_oe(1'b1, "integrated early HLDA");
    check_slow_oe(1'b1, "integrated early HLDA");

    wait_bus_phase(LOCAL_PHASE_Q2A);
    check_majority_oe(1'b0, "integrated HOLD release Q2");
    check_slow_oe(1'b1, "integrated HOLD release Q2");
    wait_bus_phase(LOCAL_PHASE_Q3A);
    check(!hlda_emua_n, "HLDA must repeat while HOLD remains active");
    check_majority_oe(1'b0, "integrated HOLD release Q3");
    check_slow_oe(1'b0, "integrated HOLD release Q3");

    held_pc = pc;
    repeat (4) begin
      @(posedge core_clk);
      #1;
      check(pc == held_pc, "processor PC changed while local bus was held");
      check(!lad_oe, "LAD drove while external master owned the bus");
      check_majority_oe(1'b0, "integrated held bus");
      check_slow_oe(1'b0, "integrated held bus");
    end

    // Deassert before end Q1. HLDA becomes inactive in the following Q3/Q4;
    // majority outputs resume at the next Q2 and DEN/DDOUT one quarter later.
    wait_bus_phase(LOCAL_PHASE_Q1A);
    hold_n = 1'b1;
    wait_bus_phase(LOCAL_PHASE_Q2A);
    check(hlda_emua_n, "HLDA did not become inactive after HOLD release");
    check_majority_oe(1'b0, "integrated release sample Q2");
    check_slow_oe(1'b0, "integrated release sample Q2");
    wait_bus_phase(LOCAL_PHASE_Q3A);
    check(hlda_emua_n, "HLDA remained active during release Q3/Q4");
    check_majority_oe(1'b0, "integrated release sample Q3");
    check_slow_oe(1'b0, "integrated release sample Q3");
    wait_bus_phase(LOCAL_PHASE_Q2A);
    check_majority_oe(1'b1, "integrated resume Q2");
    check_slow_oe(1'b0, "integrated resume Q2");
    wait_bus_phase(LOCAL_PHASE_Q3A);
    check_majority_oe(1'b1, "integrated resume Q3");
    check_slow_oe(1'b1, "integrated resume Q3");

    watchdog = 0;
    while ((pc == held_pc) && (watchdog < 100)) begin
      @(posedge core_clk);
      watchdog++;
    end
    check(pc != held_pc, "processor did not resume after physical HOLD");

    // Arm one dynamic opcode only after the live-traffic HOLD test. RUN/EMU
    // is first held low long enough to cross into the core, so that opcode
    // enters the quiescent emulator state instead of acting as a NOP.
    run_emu_n = 1'b0;
    repeat (3) @(posedge core_clk);
    emu_halt_arm = 1'b1;
    watchdog = 0;
    while ((core_state != CORE_EMU_HALT) && (watchdog < 400)) begin
      @(posedge core_clk);
      watchdog++;
    end
    check(core_state == CORE_EMU_HALT,
          "physical RUN/EMU low did not enter emulator halt");
    emu_halt_arm = 1'b0;
    held_pc = pc;

    check_emu_window("halt");
    wait_bus_phase(LOCAL_PHASE_Q1A);
    check(!hlda_emua_n, "halted EMUA did not repeat in Q1/Q2");
    wait_bus_phase(LOCAL_PHASE_Q3A);
    check(hlda_emua_n, "halted EMUA leaked into inactive-HLDA Q3/Q4");

    // Simultaneous emulator halt and HOLD exercise both halves of the shared
    // pin: EMUA owns Q1/Q2 and HLDA owns Q3/Q4.
    wait_bus_phase(LOCAL_PHASE_Q1A);
    hold_n = 1'b0;
    watchdog = 0;
    while (!((subphase == LOCAL_PHASE_Q3A) && !hlda_emua_n)
           && (watchdog < 400)) begin
      @(negedge bus_clk8x);
      watchdog++;
    end
    check(watchdog < 400, "halted HOLD did not produce Q3 HLDA");
    wait_bus_phase(LOCAL_PHASE_Q1A);
    check(!hlda_emua_n, "EMUA missing from Q1 during simultaneous HOLD");
    wait_bus_phase(LOCAL_PHASE_Q3A);
    check(!hlda_emua_n, "HLDA missing from Q3 during simultaneous halt");

    wait_bus_phase(LOCAL_PHASE_Q1A);
    hold_n = 1'b1;
    watchdog = 0;
    while (!((subphase == LOCAL_PHASE_Q3A) && hlda_emua_n)
           && (watchdog < 400)) begin
      @(negedge bus_clk8x);
      watchdog++;
    end
    check(watchdog < 400, "HLDA did not release while emulator stayed halted");
    wait_bus_phase(LOCAL_PHASE_Q1A);
    check(!hlda_emua_n, "releasing HOLD also released halted EMUA");

    // Returning RUN high leaves halt after the synchronized sample and
    // releases EMUA only on a complete Q1/Q2 boundary.
    run_emu_n = 1'b1;
    watchdog = 0;
    while ((core_state == CORE_EMU_HALT) && (watchdog < 100)) begin
      @(posedge core_clk);
      watchdog++;
    end
    check(core_state != CORE_EMU_HALT,
          "processor did not leave emulator halt");
    watchdog = 0;
    while (!((subphase == LOCAL_PHASE_Q1A) && hlda_emua_n)
           && (watchdog < 400)) begin
      @(negedge bus_clk8x);
      watchdog++;
    end
    check(watchdog < 400, "EMUA did not release on resume");
    wait_bus_phase(LOCAL_PHASE_Q3A);
    check(hlda_emua_n, "inactive HLDA missing after emulator resume");
    watchdog = 0;
    while ((pc == held_pc) && (watchdog < 100)) begin
      @(posedge core_clk);
      watchdog++;
    end
    check(pc != held_pc, "execution did not resume after emulator halt");

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
    #100000;
    $display("TEST_RESULT: FAIL (timeout)");
    $finish;
  end

endmodule : tb_pin_system

`default_nettype wire
