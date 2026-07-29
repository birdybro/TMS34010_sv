// -----------------------------------------------------------------------------
// tb_fetch_walk.sv
//
// End-to-end Phase 1 test: connects tms34010_core to sim_memory_model,
// preloads N "instructions" into the memory, runs the core, and verifies
// the PC walks 0, 16, 32, ..., (N-1)*16 — i.e. one INSTR_WORD_BITS step
// per ack.
//
// This test exercises:
//   - CORE_RESET level-0 vector read, then FETCH → DECODE → FETCH under load.
//   - PC advance by INSTR_WORD_BITS on each mem_ack.
//   - mem_addr == pc_o while in CORE_FETCH (cross-checked against PC).
//   - sim_memory_model ack timing (one-cycle pulse per request).
//
// The program uses distinct, valid single-word MOVK encodings so instruction
// execution cannot issue secondary memory requests that obscure fetch acks.
//
// Sampling strategy:
//   An `always @(posedge clk)` monitor samples in the active region of
//   each edge, so it reads pre-NBA values. On the cycle where mem_ack
//   first goes high while the core is in CORE_FETCH, both state and PC
//   are still at their pre-advance values — that's the address that was
//   actually fetched.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_fetch_walk;
  import tms34010_pkg::*;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------
  logic                          mem_req;
  logic                          mem_we;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata;
  logic [DATA_WIDTH-1:0]         mem_rdata;
  logic                          mem_ack;
  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  tms34010_core u_core (
    .clk             (clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );

  sim_memory_model #(
    .DEPTH_WORDS (32)
  ) u_mem (
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

  // ---------------------------------------------------------------------------
  // Ack monitor
  // ---------------------------------------------------------------------------
  localparam int unsigned N = 8;

  int unsigned                   acks_seen;
  logic [ADDR_WIDTH-1:0]         observed_pc_at_ack [0:N-1];
  logic [DATA_WIDTH-1:0]         observed_rdata_at_ack [0:N-1];
  logic [ADDR_WIDTH-1:0]         observed_addr_at_ack [0:N-1];

  // Active-region monitor: reads pre-NBA values so we capture the PC
  // value that was driving mem_addr when the ack arrived.
  always @(posedge clk) begin
    if (!rst && mem_ack && state_w == CORE_FETCH) begin
      if (acks_seen < N) begin
        observed_pc_at_ack[acks_seen]    = pc_w;
        observed_rdata_at_ack[acks_seen] = mem_rdata;
        observed_addr_at_ack[acks_seen]  = mem_addr;
        acks_seen++;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  int unsigned failures;
  logic [15:0] preload_word;

  initial begin : main
    acks_seen = 0;
    failures  = 0;

    // Preload instruction words.
    for (int i = 0; i < N; i++) begin
      preload_word         = 16'h1800 | i[15:0];
      u_mem.mem[i]         = preload_word;
    end

    // Run reset.
    repeat (3) @(posedge clk);
    #1;
    rst = 1'b0;

    // Wait for N acks. Worst case is ~4 cycles per ack in the current
    // placeholder loop (FETCH issues req, IDLE→ACK is +1, ack consumed,
    // DECODE→FETCH is +1, then back); add slack.
    fork
      begin
        wait (acks_seen >= N);
      end
      begin
        repeat (20 * N) @(posedge clk);
        if (acks_seen < N) begin
          $display("TEST_RESULT: FAIL: only %0d/%0d acks seen within budget (PC=%08h, state=%s)",
                   acks_seen, N, pc_w, state_w.name());
          $finish;
        end
      end
    join_any
    disable fork;

    // Slip past the NBA region of the final-ack edge so the PC advance
    // commits before we read pc_w.
    #1;

    // Check observed PC sequence.
    for (int i = 0; i < N; i++) begin
      logic [ADDR_WIDTH-1:0] expected_pc;
      logic [15:0]           expected_word;
      expected_pc   = i * 16;
      expected_word = 16'h1800 | i[15:0];

      if (observed_pc_at_ack[i] !== expected_pc) begin
        $display("TEST_RESULT: FAIL: ack #%0d: pc expected=%08h observed=%08h",
                 i, expected_pc, observed_pc_at_ack[i]);
        failures++;
      end
      if (observed_addr_at_ack[i] !== expected_pc) begin
        $display("TEST_RESULT: FAIL: ack #%0d: mem_addr expected=%08h observed=%08h",
                 i, expected_pc, observed_addr_at_ack[i]);
        failures++;
      end
      if (observed_rdata_at_ack[i][15:0] !== expected_word) begin
        $display("TEST_RESULT: FAIL: ack #%0d: rdata low16 expected=%04h observed=%04h",
                 i, expected_word, observed_rdata_at_ack[i][15:0]);
        failures++;
      end
      if (observed_rdata_at_ack[i][31:16] !== 16'h0) begin
        $display("TEST_RESULT: FAIL: ack #%0d: rdata high16 not zero (=%04h)",
                 i, observed_rdata_at_ack[i][31:16]);
        failures++;
      end
    end

    // After N acks, PC should be at N*16 (one final advance happened on
    // ack #N-1).
    if (pc_w !== (N * 16)) begin
      $display("TEST_RESULT: FAIL: final PC=%08h, expected %08h",
               pc_w, N * 16);
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (saw %0d acks, PC walked 0..%0d step 16)",
               N, (N - 1) * 16);
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  // Watchdog
  initial begin : watchdog
    #100_000;
    $display("TEST_RESULT: FAIL: tb_fetch_walk hard timeout at 100us simulated");
    $fatal(1);
  end

endmodule : tb_fetch_walk
