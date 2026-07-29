// -----------------------------------------------------------------------------
// tb_system_fabric.sv
//
// End-to-end regression for tms34010_system and tms34010_memory_fabric.
// Real core instructions boot through the aligned-word controller boundary,
// program a screen-refresh event, and run alongside automatic DRAM refresh.
// The synchronous host port performs indirect local reads through the same
// arbiter, and external HOLD quiesces the shared controller after the active
// cycle completes.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_system_fabric;
  import tms34010_pkg::*;

  localparam int unsigned DEPTH_WORDS = 512;
  localparam logic [ADDR_WIDTH-1:0] RESET_VECTOR_HIGH_ADDR =
      RESET_VECTOR_ADDR + ADDR_WIDTH'(LOCAL_WORD_WIDTH);
  localparam logic [ADDR_WIDTH-1:0] HOST_TEST_ADDR = 32'h1000_0080;

  localparam logic [ADDR_WIDTH-1:0] A_HSBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HTOTAL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HTOTAL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VEBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VEBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VSBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VSBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VTOTAL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VTOTAL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYSTRT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYSTRT) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYTAP =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYTAP) << 4);
  localparam logic [15:0] SRE_DUDATE1 =
      (16'h0001 << DPYCTL_SRE_BIT)
    | (16'h0001 << DPYCTL_DUDATE_LO);

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                      host_req;
  logic                      host_we;
  host_reg_sel_t             host_reg;
  logic [1:0]                host_be;
  local_word_t               host_wdata;
  local_word_t               host_rdata;
  logic                      host_ack;
  logic                      host_busy;
  logic                      hold_req;
  logic                      hold_ack;
  logic                      cycle_req;
  local_cycle_kind_t         cycle_kind;
  logic [ADDR_WIDTH-1:0]     cycle_addr;
  local_word_t               cycle_wdata;
  logic [13:0]               cycle_srfaddr;
  logic [15:0]               cycle_dpytap;
  logic [7:0]                cycle_dram_row;
  local_word_t               cycle_rdata;
  logic                      cycle_ack;
  core_state_t               core_state;
  logic [ADDR_WIDTH-1:0]     pc;
  instr_word_t               instr_word;
  logic                      illegal_opcode;

  tms34010_system u_system (
    .clk               (clk),
    .rst               (rst),
    .run_emu_n_i       (1'b1),
    .emua_n_o          (),
    .hcs_n_i           (1'b0),
    .host_req_i        (host_req),
    .host_we_i         (host_we),
    .host_reg_i        (host_reg),
    .host_be_i         (host_be),
    .host_wdata_i      (host_wdata),
    .host_rdata_o      (host_rdata),
    .host_ack_o        (host_ack),
    .host_busy_o       (host_busy),
    .hint_n_o          (),
    .lint1_n_i         (1'b1),
    .lint2_n_i         (1'b1),
    .dpyint_set_i      (1'b0),
    .hold_req_i        (hold_req),
    .hold_ack_o        (hold_ack),
    .video_hsync_o     (),
    .video_vsync_o     (),
    .video_hblank_o    (),
    .video_vblank_o    (),
    .video_blank_o     (),
    .cycle_req_o       (cycle_req),
    .cycle_kind_o      (cycle_kind),
    .cycle_addr_o      (cycle_addr),
    .cycle_wdata_o     (cycle_wdata),
    .cycle_srfaddr_o   (cycle_srfaddr),
    .cycle_dpytap_o    (cycle_dpytap),
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
  logic [13:0]               target_srfaddr_q;
  logic [15:0]               target_dpytap_q;
  logic [7:0]                target_dram_row_q;
  int unsigned               total_cycle_count_q;
  int unsigned               word_read_count_q;
  int unsigned               screen_count_q;
  int unsigned               dram_count_q;
  int unsigned               host_word_count_q;
  int unsigned               reset_word_count_q;
  int unsigned               protocol_failures_q;
  logic [13:0]               last_screen_srfaddr_q;
  logic [15:0]               last_screen_dpytap_q;

  logic [$clog2(DEPTH_WORDS)-1:0] target_word_index;
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
                 && (target_addr_q == HOST_TEST_ADDR)) begin
      cycle_rdata = 16'hBEEF;
    end else if ((target_kind_q == LOCAL_CYCLE_WORD_READ)
                 && (int'(target_word_index) < DEPTH_WORDS)) begin
      cycle_rdata = memory[target_word_index];
    end
  end

  // One fixed wait clock exercises the held controller contract. Plain
  // `always` permits the sim-only initialization below to share memory[].
  always @(posedge clk) begin
    if (rst) begin
      target_state_q          <= TARGET_IDLE;
      target_kind_q           <= LOCAL_CYCLE_WORD_READ;
      target_addr_q           <= '0;
      target_wdata_q          <= '0;
      target_srfaddr_q        <= '0;
      target_dpytap_q         <= '0;
      target_dram_row_q       <= '0;
      total_cycle_count_q     <= 0;
      word_read_count_q       <= 0;
      screen_count_q          <= 0;
      dram_count_q            <= 0;
      host_word_count_q       <= 0;
      reset_word_count_q      <= 0;
      protocol_failures_q     <= 0;
      last_screen_srfaddr_q   <= '0;
      last_screen_dpytap_q    <= '0;
    end else begin
      unique case (target_state_q)
        TARGET_IDLE: begin
          if (cycle_req) begin
            target_kind_q     <= cycle_kind;
            target_addr_q     <= cycle_addr;
            target_wdata_q    <= cycle_wdata;
            target_srfaddr_q  <= cycle_srfaddr;
            target_dpytap_q   <= cycle_dpytap;
            target_dram_row_q <= cycle_dram_row;
            total_cycle_count_q <= total_cycle_count_q + 1;

            if (cycle_kind == LOCAL_CYCLE_WORD_READ)
              word_read_count_q <= word_read_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_WORD_READ)
                && (cycle_addr == HOST_TEST_ADDR))
              host_word_count_q <= host_word_count_q + 1;
            if ((cycle_kind == LOCAL_CYCLE_WORD_READ)
                && ((cycle_addr == RESET_VECTOR_ADDR)
                    || (cycle_addr == RESET_VECTOR_HIGH_ADDR)))
              reset_word_count_q <= reset_word_count_q + 1;
            if (cycle_kind == LOCAL_CYCLE_SCREEN_REFRESH) begin
              screen_count_q        <= screen_count_q + 1;
              last_screen_srfaddr_q <= cycle_srfaddr;
              last_screen_dpytap_q  <= cycle_dpytap;
            end
            if ((cycle_kind == LOCAL_CYCLE_DRAM_RAS)
                || (cycle_kind == LOCAL_CYCLE_DRAM_CBR))
              dram_count_q <= dram_count_q + 1;

            target_state_q <= TARGET_WAIT;
          end
        end

        TARGET_WAIT,
        TARGET_ACK: begin
          if (!cycle_req
              || (cycle_kind != target_kind_q)
              || (cycle_addr != target_addr_q)
              || (cycle_wdata != target_wdata_q)
              || (cycle_srfaddr != target_srfaddr_q)
              || (cycle_dpytap != target_dpytap_q)
              || (cycle_dram_row != target_dram_row_q)) begin
            protocol_failures_q <= protocol_failures_q + 1;
          end

          if (target_state_q == TARGET_WAIT) begin
            target_state_q <= TARGET_ACK;
          end else begin
            if ((target_kind_q == LOCAL_CYCLE_WORD_WRITE)
                && (int'(target_word_index) < DEPTH_WORDS))
              memory[target_word_index] <= target_wdata_q;
            target_state_q <= TARGET_IDLE;
          end
        end

        default: target_state_q <= TARGET_IDLE;
      endcase
    end
  end

  function automatic instr_word_t movi_il_enc(input reg_idx_t idx);
    return 16'h09E0 | instr_word_t'(idx);
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

  function automatic int unsigned place_store_abs(
    input int unsigned p,
    input reg_idx_t    source,
    input logic [ADDR_WIDTH-1:0] store_addr
  );
    memory[p]     = 16'h0580 | instr_word_t'(source);
    memory[p + 1] = store_addr[15:0];
    memory[p + 2] = store_addr[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_io_write(
    input int unsigned p,
    input reg_idx_t    source,
    input logic [15:0] value,
    input logic [ADDR_WIDTH-1:0] io_addr
  );
    int unsigned next_p;
    begin
      next_p = place_movi_il(p, source, {16'h0000, value});
      return place_store_abs(next_p, source, io_addr);
    end
  endfunction

  int unsigned failures;

  task automatic host_cycle(
    input  logic          write_access,
    input  host_reg_sel_t selected_reg,
    input  logic [1:0]    byte_enable,
    input  local_word_t   write_data,
    output local_word_t   read_data
  );
    int unsigned watchdog;
    begin
      @(negedge clk);
      host_req   = 1'b1;
      host_we    = write_access;
      host_reg   = selected_reg;
      host_be    = byte_enable;
      host_wdata = write_data;
      watchdog = 0;
      while (!host_ack && (watchdog < 100)) begin
        @(posedge clk);
        #1;
        watchdog++;
      end
      if (!host_ack) begin
        $display("TEST_RESULT: FAIL: system host-register cycle timeout");
        failures++;
      end
      read_data = host_rdata;
      @(negedge clk);
      host_req = 1'b0;
      host_we  = 1'b0;
      host_be  = 2'b00;
      @(posedge clk);
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
      while (host_busy && (watchdog < 200)) begin
        @(posedge clk);
        #1;
        watchdog++;
      end
      if (host_busy) begin
        $display("TEST_RESULT: FAIL: system host-indirect cycle timeout");
        failures++;
      end
    end
  endtask

  initial begin : main
    int unsigned i;
    int unsigned p;
    int unsigned watchdog;
    int unsigned cycles_before_hold;
    local_word_t rd;

    failures   = 0;
    host_req   = 1'b0;
    host_we    = 1'b0;
    host_reg   = HOST_REG_HSTCTL;
    host_be    = 2'b00;
    host_wdata = '0;
    hold_req   = 1'b0;

    for (i = 0; i < DEPTH_WORDS; i++) memory[i] = 16'h0300;

    // Configure a compact noninterlaced frame. SRE is written last so no
    // screen request can capture partially programmed timing/tap state.
    p = 0;
    p = place_io_write(p, 4'd0, 16'd6, A_HSBLNK);
    p = place_io_write(p, 4'd0, 16'd7, A_HTOTAL);
    p = place_io_write(p, 4'd0, 16'd1, A_VEBLNK);
    p = place_io_write(p, 4'd0, 16'd3, A_VSBLNK);
    p = place_io_write(p, 4'd0, 16'd3, A_VTOTAL);
    p = place_io_write(p, 4'd0, {14'h0120, 2'b00}, A_DPYSTRT);
    p = place_io_write(p, 4'd0, 16'hBEEF, A_DPYTAP);
    p = place_io_write(p, 4'd0, SRE_DUDATE1, A_DPYCTL);
    p = place_movi_il(p, 4'd5, 32'h0000_0146);

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    watchdog = 0;
    while ((u_system.u_core.u_regfile.a_regs[5] !== 32'h0000_0146)
           && (watchdog < 5000)) begin
      @(posedge clk);
      watchdog++;
    end
    if (u_system.u_core.u_regfile.a_regs[5] !== 32'h0000_0146) begin
      $display("TEST_RESULT: FAIL: program did not complete through fabric");
      failures++;
    end

    watchdog = 0;
    while (((screen_count_q == 0) || (dram_count_q == 0))
           && (watchdog < 1000)) begin
      @(posedge clk);
      watchdog++;
    end
    if (screen_count_q == 0) begin
      $display("TEST_RESULT: FAIL: integrated screen client was not serviced");
      failures++;
    end else if ((last_screen_srfaddr_q !== 14'h0120)
                 || (last_screen_dpytap_q !== 16'h3EEF)) begin
      $display("TEST_RESULT: FAIL: screen payload expected=0120/3eef actual=%04h/%04h",
               last_screen_srfaddr_q, last_screen_dpytap_q);
      failures++;
    end
    if (dram_count_q == 0) begin
      $display("TEST_RESULT: FAIL: integrated DRAM refresh was not serviced");
      failures++;
    end
    if (reset_word_count_q != 2) begin
      $display("TEST_RESULT: FAIL: reset vector expected two words actual=%0d",
               reset_word_count_q);
      failures++;
    end

    // Host address completion prefetches BEEF through the shared fabric.
    host_write(HOST_REG_HSTADRL, 2'b11, HOST_TEST_ADDR[15:0]);
    host_write(HOST_REG_HSTADRH, 2'b11, HOST_TEST_ADDR[31:16]);
    wait_host_idle();
    host_read(HOST_REG_HSTDATA, rd);
    if (rd !== 16'hBEEF) begin
      $display("TEST_RESULT: FAIL: host prefetch expected=beef actual=%04h", rd);
      failures++;
    end
    wait_host_idle();
    if (host_word_count_q < 2) begin
      $display("TEST_RESULT: FAIL: expected two host fabric reads actual=%0d",
               host_word_count_q);
      failures++;
    end

    // Assert HOLD during a live CPU cycle. That cycle must finish before
    // acknowledge; once acknowledged, the controller remains quiescent.
    while ((cycle_req !== 1'b1)
           || (cycle_kind !== LOCAL_CYCLE_WORD_READ)
           || (cycle_addr == HOST_TEST_ADDR)) begin
      @(negedge clk);
    end
    hold_req = 1'b1;
    watchdog = 0;
    while (!hold_ack && (watchdog < 100)) begin
      @(posedge clk);
      watchdog++;
    end
    if (!hold_ack) begin
      $display("TEST_RESULT: FAIL: integrated HOLD acknowledge timeout");
      failures++;
    end
    cycles_before_hold = total_cycle_count_q;
    repeat (4) begin
      @(posedge clk);
      #1;
      if (!hold_ack || cycle_req) begin
        $display("TEST_RESULT: FAIL: HOLD did not keep controller quiescent");
        failures++;
      end
      if (total_cycle_count_q != cycles_before_hold) begin
        $display("TEST_RESULT: FAIL: controller accepted a cycle during HOLD");
        failures++;
      end
    end

    @(negedge clk);
    hold_req = 1'b0;
    watchdog = 0;
    while ((total_cycle_count_q == cycles_before_hold)
           && (watchdog < 100)) begin
      @(posedge clk);
      watchdog++;
    end
    if (total_cycle_count_q == cycles_before_hold) begin
      $display("TEST_RESULT: FAIL: fabric did not resume after HOLD");
      failures++;
    end

    if (word_read_count_q < 20) begin
      $display("TEST_RESULT: FAIL: insufficient CPU word traffic count=%0d",
               word_read_count_q);
      failures++;
    end
    if (protocol_failures_q != 0) begin
      $display("TEST_RESULT: FAIL: %0d integrated payload stability violation(s)",
               protocol_failures_q);
      failures++;
    end
    if (illegal_opcode !== 1'b0) begin
      $display("TEST_RESULT: FAIL: unexpected illegal opcode");
      failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (system boot, CPU/host/screen/DRAM fabric, HOLD)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : hard_timeout
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_system_fabric hard timeout");
    $fatal(1);
  end

endmodule : tb_system_fabric
