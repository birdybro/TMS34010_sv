// -----------------------------------------------------------------------------
// tb_host_integration.sv
//
// Core/I/O integration regression for the four-register host port.
// It verifies that processor HSTADR/HSTDATA accesses share the host engine
// without local side effects, host HSTCTL accesses retain Task 0142 ownership,
// and host-indirect memory/I/O reads and writes leave the core as held aligned
// word clients with completion-qualified shared-register side effects.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_host_integration;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req;
  logic                          mem_we;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata;
  logic [DATA_WIDTH-1:0]         mem_rdata;
  logic                          mem_ack;

  logic                          host_req;
  logic                          host_we;
  host_reg_sel_t                 host_reg;
  logic [1:0]                    host_be;
  local_word_t                   host_wdata;
  local_word_t                   host_rdata;
  logic                          host_ack;
  logic                          host_busy;
  logic                          hint_n;

  logic                          host_mem_req;
  logic                          host_mem_we;
  logic [ADDR_WIDTH-1:0]         host_mem_addr;
  local_word_t                   host_mem_wdata;
  logic                          host_mem_is_io;
  local_word_t                   host_mem_io_rdata;
  local_word_t                   host_mem_rdata;
  logic                          host_mem_ack;

  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  localparam logic [ADDR_WIDTH-1:0] A_HSTDATA =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTDATA) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HSTADRL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTADRL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HSTADRH =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTADRH) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HSTCTLL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTCTLL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_PSIZE =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PSIZE) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_CONTROL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_CONTROL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_RESERVED_17 =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_RESERVED_17) << 4);
  localparam logic [15:0] INCREMENT_MASK =
      (16'h0001 << HSTCTL_INCR_BIT)
    | (16'h0001 << HSTCTL_INCW_BIT);

  tms34010_core u_core (
    .clk             (clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1),
    .rst             (rst), .vclk_rst_i(rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata), .mem_srt(),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .run_emu_n_i     (1'b1),
    .emua_n_o        (),
    .hcs_n_i         (1'b0),
    .host_req_i      (host_req),
    .host_we_i       (host_we),
    .host_reg_i      (host_reg),
    .host_be_i       (host_be),
    .host_wdata_i    (host_wdata),
    .host_rdata_o    (host_rdata),
    .host_ack_o      (host_ack),
    .host_busy_o     (host_busy),
    .hint_n_o        (hint_n),
    .host_mem_req_o  (host_mem_req),
    .host_mem_we_o   (host_mem_we),
    .host_mem_addr_o (host_mem_addr),
    .host_mem_wdata_o(host_mem_wdata),
    .host_mem_is_io_o(host_mem_is_io),
    .host_mem_io_rdata_o(host_mem_io_rdata),
    .host_mem_rdata_i(host_mem_rdata),
    .host_mem_ack_i  (host_mem_ack),
    .lint1_n_i       (1'b1),
    .lint2_n_i       (1'b1),
    .dpyint_set_i    (1'b0),
    .refresh_req_o   (),
    .refresh_row_o   (),
    .refresh_cbr_o   (),
    .video_hsync_o   (),
    .video_vsync_o   (),
    .video_hblank_o  (),
    .video_vblank_o  (),
    .video_blank_o   (),
    .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ack  (mem_ack)
  );

  // One-cycle aligned-word target for the exposed host client. WAIT_DROP
  // prevents a held request from being accepted twice around its ack edge.
  typedef enum logic [1:0] {
    TARGET_IDLE      = 2'd0,
    TARGET_RESPONSE  = 2'd1,
    TARGET_WAIT_DROP = 2'd2
  } target_state_t;

  target_state_t target_state_q;
  logic [ADDR_WIDTH-1:0] target_addr_q;
  logic                  target_we_q;
  logic                  target_is_io_q;
  local_word_t           target_wdata_q;
  local_word_t           target_io_rdata_q;
  local_word_t           host_words [0:15];
  int unsigned           host_mem_request_count;
  int unsigned           host_io_request_count;

  assign host_mem_ack = (target_state_q == TARGET_RESPONSE);
  assign host_mem_rdata = target_is_io_q
      ? target_io_rdata_q
      : host_words[target_addr_q[7:4]];

  always_ff @(posedge clk) begin
    if (rst) begin
      target_state_q        <= TARGET_IDLE;
      target_addr_q         <= '0;
      target_we_q           <= 1'b0;
      target_is_io_q        <= 1'b0;
      target_wdata_q        <= '0;
      target_io_rdata_q     <= '0;
      host_mem_request_count <= 0;
      host_io_request_count  <= 0;
    end else begin
      unique case (target_state_q)
        TARGET_IDLE: begin
          if (host_mem_req) begin
            target_addr_q          <= host_mem_addr;
            target_we_q            <= host_mem_we;
            target_is_io_q         <= host_mem_is_io;
            target_wdata_q         <= host_mem_wdata;
            target_io_rdata_q      <= host_mem_io_rdata;
            host_mem_request_count <= host_mem_request_count + 1;
            if (host_mem_is_io)
              host_io_request_count <= host_io_request_count + 1;
            target_state_q         <= TARGET_RESPONSE;
          end
        end

        TARGET_RESPONSE: begin
          if (target_we_q && !target_is_io_q)
            host_words[target_addr_q[7:4]] <= target_wdata_q;
          target_state_q <= TARGET_WAIT_DROP;
        end

        TARGET_WAIT_DROP: begin
          if (!host_mem_req) target_state_q <= TARGET_IDLE;
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
    u_mem.mem[p]     = movi_il_enc(idx);
    u_mem.mem[p + 1] = immediate[15:0];
    u_mem.mem[p + 2] = immediate[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_store_abs(
    input int unsigned p,
    input reg_idx_t    source,
    input logic [ADDR_WIDTH-1:0] store_addr
  );
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(source);
    u_mem.mem[p + 1] = store_addr[15:0];
    u_mem.mem[p + 2] = store_addr[31:16];
    return p + 3;
  endfunction

  function automatic int unsigned place_load_abs(
    input int unsigned p,
    input reg_idx_t    destination,
    input logic [ADDR_WIDTH-1:0] load_addr
  );
    u_mem.mem[p]     = 16'h05A0 | instr_word_t'(destination);
    u_mem.mem[p + 1] = load_addr[15:0];
    u_mem.mem[p + 2] = load_addr[31:16];
    return p + 3;
  endfunction

  int unsigned failures;

  task automatic check_bit(
    input string label,
    input logic  actual,
    input logic  expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%0b actual=%0b",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic check_word(
    input string       label,
    input local_word_t actual,
    input local_word_t expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%04h actual=%04h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic check_addr(
    input string                 label,
    input logic [ADDR_WIDTH-1:0] actual,
    input logic [ADDR_WIDTH-1:0] expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%08h actual=%08h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic host_cycle(
    input  logic          write_access,
    input  host_reg_sel_t selected_reg,
    input  logic [1:0]    byte_enable,
    input  local_word_t   write_data,
    output local_word_t   read_data
  );
    int unsigned wait_cycles;
    begin
      @(negedge clk);
      host_req   = 1'b1;
      host_we    = write_access;
      host_reg   = selected_reg;
      host_be    = byte_enable;
      host_wdata = write_data;
      wait_cycles = 0;
      while (!host_ack && (wait_cycles < 100)) begin
        @(posedge clk);
        #1;
        wait_cycles++;
      end
      if (!host_ack) begin
        $display("TEST_RESULT: FAIL: integrated host access timed out");
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
    int unsigned wait_cycles;
    begin
      wait_cycles = 0;
      while (host_busy && (wait_cycles < 100)) begin
        @(posedge clk);
        #1;
        wait_cycles++;
      end
      if (host_busy) begin
        $display("TEST_RESULT: FAIL: integrated host memory cycle timed out");
        failures++;
      end
    end
  endtask

  initial begin : main
    int unsigned p;
    int unsigned i;
    int unsigned io_requests_before;
    local_word_t rd;

    failures   = 0;
    host_req   = 1'b0;
    host_we    = 1'b0;
    host_reg   = HOST_REG_HSTCTL;
    host_be    = 2'b00;
    host_wdata = '0;

    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 0; i < 16; i++) host_words[i] = '0;
    host_words[8]  = 16'h1111;
    host_words[9]  = 16'h2222;
    host_words[11] = 16'hBEEF;

    // Processor writes all three host-engine registers and HSTCTLL directly.
    // The HSTADR low nibble must be forced to zero, and none of these writes
    // may create a host local-word request.
    p = 0;
    p = place_movi_il(p, 4'd0, 32'h0000_00BF);
    p = place_store_abs(p, 4'd0, A_HSTADRL);
    p = place_movi_il(p, 4'd1, 32'h0000_1234);
    p = place_store_abs(p, 4'd1, A_HSTADRH);
    p = place_movi_il(p, 4'd2, 32'h0000_CAFE);
    p = place_store_abs(p, 4'd2, A_HSTDATA);
    p = place_load_abs(p, 4'd3, A_HSTDATA);
    p = place_movi_il(p, 4'd4, 32'h0000_00D0);
    p = place_store_abs(p, 4'd4, A_HSTCTLL);
    p = place_movi_il(p, 4'd6, 32'h0000_0007);
    p = place_store_abs(p, 4'd6, A_PSIZE);
    p = place_movi_il(p, 4'd5, 32'h0000_0144);
    u_mem.mem[p] = 16'hC0FF;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    wait (u_core.u_regfile.a_regs[5] == 32'h0000_0144);
    repeat (3) @(posedge clk);
    #1;

    check_bit("processor host-register access raises no host request",
              host_mem_request_count != 0, 1'b0);
    check_bit("processor INTOUT drives HINT", hint_n, 1'b0);

    host_read(HOST_REG_HSTADRL, rd);
    check_word("host sees processor HSTADRL alignment", rd, 16'h00B0);
    host_read(HOST_REG_HSTADRH, rd);
    check_word("host sees processor HSTADRH", rd, 16'h1234);
    host_read(HOST_REG_HSTDATA, rd);
    check_word("host sees processor HSTDATA", rd, 16'hCAFE);
    wait_host_idle();
    check_addr("host HSTDATA read uses shared processor pointer",
               target_addr_q, 32'h1234_00B0);
    check_word("host HSTDATA read updates shared buffer",
               u_core.u_io_regs.u_host_if.hstdata_q, 16'hBEEF);

    // Direct HSTCTL goes through the generic four-register port while
    // retaining complementary low-byte ownership and HINT behavior.
    host_read(HOST_REG_HSTCTL, rd);
    check_word("host sees processor MSGOUT/INTOUT", rd, 16'h00D0);
    host_write(HOST_REG_HSTCTL, 2'b01, 16'h000D);
    host_read(HOST_REG_HSTCTL, rd);
    check_word("integrated host low-byte ownership", rd, 16'h005D);
    check_bit("host clears INTOUT/HINT", hint_n, 1'b1);
    host_write(HOST_REG_HSTCTL, 2'b10, INCREMENT_MASK);
    host_read(HOST_REG_HSTCTL, rd);
    check_word("integrated increment controls", rd, 16'h185D);

    // Completing the host address prefetches word 0x80. Reading HSTDATA
    // returns that word and, because INCR is set, fetches word 0x90.
    host_write(HOST_REG_HSTADRL, 2'b11, 16'h0080);
    check_bit("LBL0 low address write has no side effect",
              host_busy, 1'b0);
    host_write(HOST_REG_HSTADRH, 2'b11, 16'h0000);
    wait_host_idle();
    check_addr("integrated address prefetch", target_addr_q, 32'h0000_0080);
    host_read(HOST_REG_HSTDATA, rd);
    check_word("integrated prefetched HSTDATA", rd, 16'h1111);
    wait_host_idle();
    check_addr("integrated INCR read", target_addr_q, 32'h0000_0090);
    host_read(HOST_REG_HSTADRL, rd);
    check_word("integrated INCR pointer", rd, 16'h0090);
    check_word("integrated INCR updates buffer",
               u_core.u_io_regs.u_host_if.hstdata_q, 16'h2222);

    // INCW writes at the current address and increments only after the local
    // target acknowledges completion.
    host_write(HOST_REG_HSTDATA, 2'b11, 16'hABCD);
    wait_host_idle();
    check_addr("integrated host write address", target_addr_q, 32'h0000_0090);
    check_word("integrated host write data", host_words[9], 16'hABCD);
    host_read(HOST_REG_HSTADRL, rd);
    check_word("integrated INCW postincrement", rd, 16'h00A0);
    check_addr("integrated local request count",
               ADDR_WIDTH'(host_mem_request_count), 32'd4);

    // §6.1 permits the host to indirect through the same I/O page. HSTCTLL
    // retains host-side field ownership even through that route: MSGIN is
    // replaced while processor-owned MSGOUT remains intact.
    host_write(HOST_REG_HSTCTL, 2'b10, 16'h0000);
    host_write(HOST_REG_HSTADRL, 2'b11, A_HSTCTLL[15:0]);
    host_write(HOST_REG_HSTADRH, 2'b11, A_HSTCTLL[31:16]);
    wait_host_idle();
    host_write(HOST_REG_HSTDATA, 2'b11, 16'h0003);
    wait_host_idle();
    host_read(HOST_REG_HSTCTL, rd);
    check_word("host-indirect HSTCTLL ownership", rd, 16'h005B);

    // Point at PSIZE and prove the internal word is returned, then prove a
    // write changes PSIZE only through the acknowledged physical client.
    host_write(HOST_REG_HSTADRL, 2'b11, A_PSIZE[15:0]);
    host_write(HOST_REG_HSTADRH, 2'b11, A_PSIZE[31:16]);
    wait_host_idle();
    check_bit("host-indirect PSIZE classified as I/O",
              target_is_io_q, 1'b1);
    check_addr("host-indirect PSIZE read address",
               target_addr_q, A_PSIZE);
    check_word("host-indirect PSIZE internal read payload",
               target_io_rdata_q, 16'h0007);
    host_read(HOST_REG_HSTDATA, rd);
    check_word("host receives host-indirect PSIZE", rd, 16'h0007);
    wait_host_idle();

    host_write(HOST_REG_HSTDATA, 2'b11, 16'h0009);
    check_word("host-indirect PSIZE unchanged before physical ack",
               u_core.u_io_regs.io_reg[IO_IDX_PSIZE], 16'h0007);
    wait_host_idle();
    check_bit("host-indirect PSIZE write remains I/O",
              target_is_io_q, 1'b1);
    check_bit("host-indirect PSIZE write intent",
              target_we_q, 1'b1);
    check_word("host-indirect PSIZE write payload",
               target_wdata_q, 16'h0009);
    check_word("host-indirect PSIZE write commits on ack",
               u_core.u_io_regs.io_reg[IO_IDX_PSIZE], 16'h0009);
    check_addr("host-indirect I/O request count",
               ADDR_WIDTH'(host_io_request_count), 32'd5);

    // Host-indirect accesses observe the same ordinary-register write masks
    // as processor accesses. Re-prefetch after the write so HSTDATA contains
    // the stored, masked CONTROL value rather than the raw write buffer.
    io_requests_before = host_io_request_count;
    host_write(HOST_REG_HSTADRL, 2'b11, A_CONTROL[15:0]);
    host_write(HOST_REG_HSTADRH, 2'b11, A_CONTROL[31:16]);
    wait_host_idle();
    host_write(HOST_REG_HSTDATA, 2'b11, 16'hFFFF);
    wait_host_idle();
    check_word("host-indirect CONTROL stored reserved bits low",
               u_core.u_io_regs.io_reg[IO_IDX_CONTROL],
               CONTROL_WRITABLE_MASK);
    host_write(HOST_REG_HSTADRH, 2'b11, A_CONTROL[31:16]);
    wait_host_idle();
    host_read(HOST_REG_HSTDATA, rd);
    check_word("host-indirect CONTROL read returns masked value",
               rd, CONTROL_WRITABLE_MASK);
    wait_host_idle();

    // Figure 6-1 reserves 17h and the PMASK description says its compatibility
    // write has no effect. Both the prefetched read and state after an
    // acknowledged write must remain zero.
    host_write(HOST_REG_HSTADRL, 2'b11, A_RESERVED_17[15:0]);
    host_write(HOST_REG_HSTADRH, 2'b11, A_RESERVED_17[31:16]);
    wait_host_idle();
    host_read(HOST_REG_HSTDATA, rd);
    check_word("host-indirect reserved prefetch returns zero",
               rd, 16'h0000);
    wait_host_idle();
    host_write(HOST_REG_HSTDATA, 2'b11, 16'hBEEF);
    wait_host_idle();
    check_word("host-indirect reserved write has no storage effect",
               u_core.u_io_regs.io_reg[IO_IDX_RESERVED_17], 16'h0000);
    host_write(HOST_REG_HSTADRH, 2'b11, A_RESERVED_17[31:16]);
    wait_host_idle();
    host_read(HOST_REG_HSTDATA, rd);
    check_word("host-indirect reserved reread remains zero",
               rd, 16'h0000);
    wait_host_idle();
    check_addr("host-indirect mask/reserved request count",
               ADDR_WIDTH'(host_io_request_count - io_requests_before),
               32'd9);

    check_bit("no illegal opcode", illegal_w, 1'b0);
    if (failures == 0) begin
      $display("TEST_RESULT: PASS (core/I/O four-register host integration and local-word client)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_host_integration hard timeout");
    $fatal(1);
  end

endmodule : tb_host_integration
