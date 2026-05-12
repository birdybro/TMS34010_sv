// -----------------------------------------------------------------------------
// tb_illegal_opcode.sv
//
// Verifies the Phase 3 decode skeleton's illegal-opcode path:
//   1. After reset, `illegal_opcode_o` is 0.
//   2. The core fetches the first instruction word from memory.
//   3. Decode flags the encoding ILLEGAL (Phase 3 skeleton flags everything
//      as illegal — no SPVU004 opcode-chart rows are populated yet).
//   4. When the core transitions through CORE_DECODE, the sticky
//      `illegal_opcode_o` latches high and stays high.
//   5. The FSM still walks DECODE → EXECUTE → WRITEBACK → FETCH (the
//      skeleton does not halt on illegal; it just flags). Successive
//      fetches still happen.
//   6. `instr_word_o` matches what was preloaded into memory.
//
// Real illegal-opcode trap semantics (vector to a handler, save ST/PC,
// etc.) is Phase 8 work — see docs/assumptions.md A0008. For now we just
// verify the visibility output.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_illegal_opcode;
  import tms34010_pkg::*;

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
    .clk             (clk),
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
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(32)) u_mem (
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
  // Test body
  // ---------------------------------------------------------------------------
  int unsigned failures;
  bit          saw_illegal;
  bit          saw_pc_advance;
  bit          saw_instr_latched;

  // Watchdog snapshot of `illegal_w` once it goes high — used to confirm
  // stickiness. Also capture the first instr_word_q ever latched, so we
  // can verify it equals the preloaded word at PC=0 (=DEAD).
  bit                     illegal_first_seen;
  int unsigned            illegal_first_seen_cycle;
  int unsigned            cycle_count;
  bit                     first_instr_captured;
  instr_word_t            first_instr_latched;

  always @(posedge clk) begin
    if (!rst) begin
      cycle_count++;
      if (illegal_w && !illegal_first_seen) begin
        illegal_first_seen       <= 1'b1;
        illegal_first_seen_cycle <= cycle_count;
      end
      if (illegal_first_seen && !illegal_w) begin
        $display("TEST_RESULT: FAIL: illegal_opcode_o dropped after going high (cycle=%0d)",
                 cycle_count);
        failures++;
      end
      // Capture the first instruction word seen in CORE_DECODE — this
      // is the word that was just fetched at PC=0.
      if (!first_instr_captured && state_w == CORE_DECODE) begin
        first_instr_captured <= 1'b1;
        first_instr_latched  <= instr_w;
      end
    end
  end

  initial begin : main
    failures                  = 0;
    saw_illegal               = 1'b0;
    saw_pc_advance            = 1'b0;
    saw_instr_latched         = 1'b0;
    illegal_first_seen        = 1'b0;
    illegal_first_seen_cycle  = 0;
    cycle_count               = 0;
    first_instr_captured      = 1'b0;
    first_instr_latched       = '0;

    // Preload distinct "nonsense" instruction words. Every value should
    // decode as ILLEGAL in the Phase 3 skeleton.
    u_mem.mem[0] = 16'hDEAD;
    u_mem.mem[1] = 16'hBEEF;
    u_mem.mem[2] = 16'h1234;
    u_mem.mem[3] = 16'h5678;

    // After reset, illegal_w must be 0.
    repeat (3) @(posedge clk);
    #1;
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o = %0b during reset (expected 0)",
               illegal_w);
      failures++;
    end

    rst = 1'b0;

    // Run for enough cycles to comfortably let the first instruction
    // word be fetched, decoded, and execute. With a 5-cycle FSM period
    // per instruction in the current placeholder loop, ~30 cycles is
    // plenty.
    repeat (30) @(posedge clk);
    #1;

    if (!illegal_first_seen) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o never asserted (state=%s, pc=%08h, instr=%04h)",
               state_w.name(), pc_w, instr_w);
      failures++;
    end

    // The first instruction word observed in CORE_DECODE should be
    // the value preloaded at mem[0] = 0xDEAD.
    if (!first_instr_captured) begin
      $display("TEST_RESULT: FAIL: first CORE_DECODE never observed");
      failures++;
    end else if (first_instr_latched !== 16'hDEAD) begin
      $display("TEST_RESULT: FAIL: first instr_word_o was %04h, expected DEAD",
               first_instr_latched);
      failures++;
    end

    // The PC should have advanced past the first instruction.
    if (pc_w === '0) begin
      $display("TEST_RESULT: FAIL: PC never advanced from reset value");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (illegal asserted at cycle %0d; first_instr=%04h; final pc=%08h)",
               illegal_first_seen_cycle, first_instr_latched, pc_w);
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #100_000;
    $display("TEST_RESULT: FAIL: tb_illegal_opcode hard timeout");
    $fatal(1);
  end

endmodule : tb_illegal_opcode
