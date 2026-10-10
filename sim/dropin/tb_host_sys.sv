// -----------------------------------------------------------------------------
// tb_host_sys.sv
//
// The host interface through tms34010_system, in either mode (chapter 10).
// A host loads a program and its vectors through HSTADR/HSTDATA while the
// 34010 is held by the host-present reset (HCS high, 8.8), reads it back,
// releases HLT, and then, while the 34010 runs:
//   - halts and resumes it many times at different phases, measuring the halt
//     latency from the host's HSTCTL write to the halted state (10.3.4);
//   - reads and writes local memory through HSTADR/HSTDATA, measuring how long
//     the host engine is busy (10.3.3, 10.4, 10.5);
//   - raises NMI and the host interrupt (INTIN), checking the handlers run and
//     the program carries on (8.1, 8.3, 10.2).
// Program: tools/dropin/host_prog.py -> +PROG=<file>.
// Prints MEAS lines (in clocks and machine states) and TEST_RESULT.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_host_sys;
  import tms34010_pkg::*;

  parameter int unsigned ACK_DELAY      = 1;
  parameter bit          CYCLE_ACCURATE = 1'b1;
  parameter int unsigned CLKS_PER_STATE = 8;
  localparam int unsigned CPS = CYCLE_ACCURATE ? CLKS_PER_STATE : 1;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #1 clk = ~clk;

  logic                  cycle_req, cycle_ack, cycle_iaq;
  local_cycle_kind_t     cycle_kind;
  logic [ADDR_WIDTH-1:0] cycle_addr, pc;
  local_word_t           cycle_wdata, cycle_io_rdata, cycle_rdata;
  core_state_t           core_state;

  logic          host_req = 1'b0, host_we = 1'b0;
  host_reg_sel_t host_reg = HOST_REG_HSTADRL;
  local_word_t   host_wdata = '0;
  local_word_t   host_rdata;
  logic          host_ack, host_busy, hint_n;

  tms34010_system #(
    .CLKS_PER_STATE (CPS),
    .CYCLE_ACCURATE (CYCLE_ACCURATE)
  ) u_system (
    .clk(clk), .vclk_i(clk), .rst(rst), .vclk_rst_i(rst),
    .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .run_emu_n_i(1'b1), .emua_n_o(),
    .hcs_n_i(1'b1),
    .host_req_i(host_req), .host_we_i(host_we), .host_reg_i(host_reg), .host_be_i(2'b11),
    .host_wdata_i(host_wdata), .host_rdata_o(host_rdata), .host_ack_o(host_ack),
    .host_busy_o(host_busy), .hint_n_o(hint_n),
    .lint1_n_i(1'b1), .lint2_n_i(1'b1), .dpyint_set_i(1'b0),
    .hold_req_i(1'b0), .hold_ack_o(),
    .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(),
    .video_hsync_oe_o(), .video_vsync_oe_o(),
    .cycle_req_o(cycle_req), .cycle_kind_o(cycle_kind), .cycle_addr_o(cycle_addr),
    .cycle_wdata_o(cycle_wdata), .cycle_io_rdata_o(cycle_io_rdata), .cycle_iaq_o(cycle_iaq),
    .cycle_srfaddr_o(), .cycle_dpytap_o(), .cycle_screen_org_o(), .cycle_dram_row_o(),
    .cycle_rdata_i(cycle_rdata), .cycle_ack_i(cycle_ack),
    .state_o(core_state), .pc_o(pc), .instr_word_o(), .illegal_opcode_o()
  );

  // ---- local memory: ACK_DELAY clocks per cycle (as tb_accuracy) ----------
  local_word_t mem [int unsigned];
  typedef enum logic [1:0] {T_IDLE, T_BUSY, T_ACK} tstate_t;
  tstate_t               t_state;
  int unsigned           t_count;
  local_cycle_kind_t     t_kind;
  logic [ADDR_WIDTH-1:0] t_addr;
  local_word_t           t_wdata, t_io_rdata;
  function automatic local_word_t rd(logic [ADDR_WIDTH-1:0] a);
    int unsigned w = a >> 4;
    if (mem.exists(w)) return mem[w];
    return 16'h0000;
  endfunction
  assign cycle_ack   = (t_state == T_ACK);
  assign cycle_rdata = (t_kind == LOCAL_CYCLE_IO_READ) ? t_io_rdata : rd(t_addr);
  always @(posedge clk) begin
    if (rst) begin
      t_state <= T_IDLE;
      t_count <= 0;
    end else begin
      case (t_state)
        T_IDLE: if (cycle_req) begin
          t_kind <= cycle_kind; t_addr <= cycle_addr; t_wdata <= cycle_wdata;
          t_io_rdata <= cycle_io_rdata; t_count <= 1;
          t_state <= (ACK_DELAY <= 1) ? T_ACK : T_BUSY;
        end
        T_BUSY: begin
          t_count <= t_count + 1;
          if (t_count + 1 >= ACK_DELAY) t_state <= T_ACK;
        end
        T_ACK: begin
          if (t_kind == LOCAL_CYCLE_WORD_WRITE) mem[t_addr >> 4] = t_wdata;
          t_state <= T_IDLE;
        end
        default: t_state <= T_IDLE;
      endcase
    end
  end

  longint unsigned now;
  always @(posedge clk) now <= rst ? 0 : now + 1;

  // ---- host side ---------------------------------------------------------
  int failures = 0;
  task automatic fail(string m);
    $display("TEST_RESULT: FAIL: %s", m);
    failures++;
  endtask

  longint unsigned acc_at;   // clock of the last host acceptance
  task automatic hacc(host_reg_sel_t r, bit we, local_word_t d, output local_word_t q);
    @(negedge clk);
    host_req = 1'b1; host_we = we; host_reg = r; host_wdata = d;
    do @(negedge clk); while (!host_ack);
    q = host_rdata;
    acc_at = now;
    host_req = 1'b0;
    @(negedge clk);
  endtask
  task automatic hw(host_reg_sel_t r, local_word_t d);
    local_word_t q;
    hacc(r, 1'b1, d, q);
  endtask
  task automatic hr(host_reg_sel_t r, output local_word_t q);
    hacc(r, 1'b0, 16'h0000, q);
  endtask
  task automatic set_addr(logic [31:0] a);
    hw(HOST_REG_HSTADRL, a[15:0]);
    hw(HOST_REG_HSTADRH, a[31:16]);
  endtask
  task automatic wait_idle();
    while (host_busy) @(negedge clk);
  endtask

  localparam local_word_t INCW = 16'h0800, INCR = 16'h1000, HLT = 16'h8000, NMI = 16'h0100;

  int unsigned n_prog;
  logic [31:0] p_addr [0:255];
  local_word_t p_word [0:255];
  string prog;

  // busy spans of the host engine (indirect cycles), in clocks
  longint unsigned busy_from;
  int busy_min = 1 << 30, busy_max = 0;
  always @(posedge clk) begin
    if (!rst && host_ack && host_busy) busy_from <= now;
  end

  initial begin
    int fd, k, lat, lat_min, lat_max, settle, settle_max = 0, settled_late = 0;
    logic [31:0] a;
    local_word_t w, q, prev, prev_hi;
    longint unsigned t0;

    if (!$value$plusargs("PROG=%s", prog)) prog = "work/host_prog.txt";
    fd = $fopen(prog, "r");
    n_prog = 0;
    while ($fscanf(fd, "%h %h", a, w) == 2) begin
      p_addr[n_prog] = a; p_word[n_prog] = w; n_prog++;
    end
    $fclose(fd);

    repeat (4) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    repeat (20) @(negedge clk);
    if (core_state == CORE_FETCH || core_state == CORE_DECODE)
      fail("34010 ran with HCS high at reset (8.8: host-present reset halts)");

    // 1. load the program (words in address order, runs of consecutive words)
    hw(HOST_REG_HSTCTL, HLT | INCW);
    for (int i = 0; i < n_prog; i++) begin
      if (i == 0 || p_addr[i] != p_addr[i-1] + 1) set_addr(p_addr[i] << 4);
      hw(HOST_REG_HSTDATA, p_word[i]);
    end
    // 2. read it back: INCR, the prefetch starts with the HSTADRH write (LBL=0, 10.3.5)
    hw(HOST_REG_HSTCTL, HLT | INCR);
    for (int i = 0; i < n_prog; i++) begin
      if (i == 0 || p_addr[i] != p_addr[i-1] + 1) set_addr(p_addr[i] << 4);
      wait_idle();
      hr(HOST_REG_HSTDATA, q);
      if (q !== p_word[i]) begin
        fail($sformatf("readback %08h: %04h, wrote %04h", p_addr[i] << 4, q, p_word[i]));
        break;
      end
    end
    // 3. release HLT: the 34010 fetches the reset vector and runs
    hw(HOST_REG_HSTCTL, 16'h0000);
    t0 = now;
    while (rd(32'h0020_0000) < 16'd200 && now < t0 + 400000) @(negedge clk);
    if (rd(32'h0020_0000) < 16'd200) fail("program did not run after HLT was cleared");

    // 4. halt latency: from the host's acceptance of the HSTCTL write to the
    //    halted state, at 64 different phases of the loop
    lat_min = 1 << 30; lat_max = 0;
    for (k = 0; k < 64; k++) begin
      repeat (13 + k * 7 % 61) @(negedge clk);
      hw(HOST_REG_HSTCTL, HLT);
      while (core_state != CORE_HOST_HALT && now < acc_at + 10000) @(negedge clk);
      if (core_state != CORE_HOST_HALT) begin fail("HLT did not halt"); break; end
      lat = int'(now - acc_at);
      if (lat < lat_min) lat_min = lat;
      if (lat > lat_max) lat_max = lat;
      // A write the halted instruction posted may still finish its bus cycles
      // (5.5): record when the last word of the 32-bit counter lands after the
      // halt, then the memory must stay still. The figure is a measurement;
      // the guide gives no bound for it. The sanity limit of 10 states is
      // generous: the two word cycles, plus refresh, screen refresh and host
      // cycles that outrank the CPU (11.3).
      prev = rd(32'h0020_0000);
      prev_hi = rd(32'h0020_0010);
      settle = 0;
      for (int c = 1; c <= 120; c++) begin
        @(negedge clk);
        if (rd(32'h0020_0000) != prev || rd(32'h0020_0010) != prev_hi) begin
          settle = c; prev = rd(32'h0020_0000); prev_hi = rd(32'h0020_0010);
        end
      end
      if (settle > settle_max) settle_max = settle;
      if (settle > 0) settled_late++;
      if (settle > 10 * CPS) fail($sformatf("memory changed %0d clocks after the halt", settle));
      repeat (50) @(negedge clk);
      if (rd(32'h0020_0000) != prev || rd(32'h0020_0010) != prev_hi) fail("memory changed while halted");
      hw(HOST_REG_HSTCTL, 16'h0000);
    end
    $display("MEAS halt_latency clocks min=%0d max=%0d states min=%0.2f max=%0.2f (64 trials, from host acceptance)",
             lat_min, lat_max, real'(lat_min) / CPS, real'(lat_max) / CPS);
    $display("MEAS halt posted_write_after_halt trials=%0d latest_clocks=%0d (%0.2f states)",
             settled_late, settle_max, real'(settle_max) / CPS);

    // 5. indirect reads and writes while the 34010 runs
    hw(HOST_REG_HSTCTL, INCR);
    prev = 0;
    for (k = 0; k < 32; k++) begin
      repeat (5 + k * 11 % 23) @(negedge clk);
      set_addr(32'h0020_0000);                    // prefetch read starts here
      t0 = acc_at;
      wait_idle();
      if (int'(now - t0) < busy_min) busy_min = int'(now - t0);
      if (int'(now - t0) > busy_max) busy_max = int'(now - t0);
      hr(HOST_REG_HSTDATA, q);
      if (q < prev) fail($sformatf("host read of the counter went backwards %04h -> %04h", prev, q));
      prev = q;
    end
    $display("MEAS host_read busy clocks min=%0d max=%0d states min=%0.2f max=%0.2f (32 reads, running)",
             busy_min, busy_max, real'(busy_min) / CPS, real'(busy_max) / CPS);
    busy_min = 1 << 30; busy_max = 0;
    hw(HOST_REG_HSTCTL, INCW);
    set_addr(32'h0030_0000);
    for (k = 0; k < 32; k++) begin
      repeat (5 + k * 11 % 23) @(negedge clk);
      wait_idle();
      hw(HOST_REG_HSTDATA, 16'h5A00 + k[15:0]);
      t0 = acc_at;
      wait_idle();
      if (int'(now - t0) < busy_min) busy_min = int'(now - t0);
      if (int'(now - t0) > busy_max) busy_max = int'(now - t0);
    end
    for (k = 0; k < 32; k++)
      if (rd(32'h0030_0000 + 16 * k) !== 16'h5A00 + k[15:0]) begin
        fail($sformatf("host write %0d not in memory", k)); break;
      end
    $display("MEAS host_write busy clocks min=%0d max=%0d states min=%0.2f max=%0.2f (32 writes, running)",
             busy_min, busy_max, real'(busy_min) / CPS, real'(busy_max) / CPS);

    // 6. NMI from the host (NMIM=0: context pushed, 8.1/10.2)
    hw(HOST_REG_HSTCTL, NMI);
    t0 = now;
    while (u_system.u_core.u_regfile.a_regs[4] != 1 && now < t0 + 20000) @(negedge clk);
    if (u_system.u_core.u_regfile.a_regs[4] != 1 || u_system.u_core.u_regfile.a_regs[5] != 32'hAAAA)
      fail("NMI handler did not run");
    else $display("MEAS nmi handler_reached clocks=%0d", now - t0);
    prev = rd(32'h0020_0000);
    repeat (400) @(negedge clk);
    if (rd(32'h0020_0000) == prev) fail("program did not resume after NMI");

    // 7. host interrupt (INTIN, HIE enabled by the program)
    hw(HOST_REG_HSTCTL, 16'h0008);
    t0 = now;
    while (u_system.u_core.u_regfile.a_regs[6] != 1 && now < t0 + 20000) @(negedge clk);
    if (u_system.u_core.u_regfile.a_regs[6] != 1) fail("host interrupt handler did not run");
    else $display("MEAS host_interrupt handler_reached clocks=%0d", now - t0);
    repeat (400) @(negedge clk);
    hr(HOST_REG_HSTCTL, q);
    if (q[3]) fail("INTIN not cleared by the handler");
    if (u_system.u_core.u_regfile.a_regs[6] != 1) fail("host interrupt taken more than once");

    // 8. INTOUT/HINT: the handler set INTOUT; HINT is low until the host clears it (10.2)
    if (hint_n !== 1'b0) fail("HINT not asserted after the 34010 set INTOUT");
    if (!q[7]) fail("host does not see INTOUT");
    hw(HOST_REG_HSTCTL, 16'h0000);
    repeat (4) @(negedge clk);
    if (hint_n !== 1'b1) fail("HINT still asserted after the host cleared INTOUT");

    // 9. CF: the host rewrites the low immediate word of the loop's ADDI (1 -> 2).
    //    With the 5.4 cache the old copy keeps running until the host flushes it
    //    (5.4.5); then the counter's low word steps by 2.
    hw(HOST_REG_HSTCTL, INCW);
    set_addr(32'h0010_0100);                    // LOOP + 16: ADDI's low immediate word
    hw(HOST_REG_HSTDATA, 16'h0002);
    repeat (40) @(negedge clk);
    begin
      local_word_t c1, c2;
      int odd = 0;
      c1 = rd(32'h0020_0000);
      for (int i = 0; i < 40; i++) begin
        repeat (CPS * 7) @(negedge clk);
        c2 = rd(32'h0020_0000);
        if ((c2 - c1) % 2) odd++;
        c1 = c2;
      end
      $display("MEAS cf before_flush odd_steps=%0d of 40 (%s)", odd,
               odd ? "old code still running from the cache" : "new code already running");
      hw(HOST_REG_HSTCTL, 16'h4000);              // CF=1: flush, and fetch around the cache while set
      repeat (CPS * 20) @(negedge clk);
      hw(HOST_REG_HSTCTL, 16'h0000);
      repeat (CPS * 20) @(negedge clk);
      odd = 0;
      c1 = rd(32'h0020_0000);
      for (int i = 0; i < 40; i++) begin
        repeat (CPS * 7) @(negedge clk);
        c2 = rd(32'h0020_0000);
        if ((c2 - c1) % 2) odd++;
        c1 = c2;
      end
      if (odd) fail($sformatf("after CF the loop still counts by 1 (%0d odd steps)", odd));
    end

    // 10. LBL=1 (Atari and Inder hosts set it): with LBL=1 the read is started by
    //     the write of HSTADRL, so the host writes HSTADRH first (10.3.5). The
    //     target is in a page HSTADRH did not hold before, so if the core started
    //     the read on the HSTADRH write (LBL ignored) it would read a stale address.
    hw(HOST_REG_HSTCTL, 16'h2000 | INCW);
    hw(HOST_REG_HSTADRH, 16'h0050); hw(HOST_REG_HSTADRL, 16'h0000);
    for (k = 0; k < 16; k++) hw(HOST_REG_HSTDATA, 16'hC300 + k[15:0]);
    hw(HOST_REG_HSTCTL, 16'h2000 | INCR);
    hw(HOST_REG_HSTADRL, 16'h0100); hw(HOST_REG_HSTADRH, 16'h0040);   // park elsewhere (both halves differ)
    hw(HOST_REG_HSTADRH, 16'h0050); hw(HOST_REG_HSTADRL, 16'h0000);   // then LBL=1 order
    for (k = 0; k < 16; k++) begin
      wait_idle();
      hr(HOST_REG_HSTDATA, q);
      if (q !== 16'hC300 + k[15:0]) begin fail($sformatf("LBL=1 readback %0d: %04h", k, q)); break; end
    end
    for (k = 0; k < 16; k++)
      if (rd(32'h0050_0000 + 16 * k) !== 16'hC300 + k[15:0]) begin
        fail($sformatf("LBL=1 write %0d not in memory", k)); break;
      end

    // 11. NMI with NMIM=1 (Exterminator's slave, JPM): no context is saved (8.1)
    begin
      logic [31:0] sp0;
      hw(HOST_REG_HSTCTL, 16'h0000);
      sp0 = u_system.u_core.rf_sp;
      hw(HOST_REG_HSTCTL, NMI | 16'h0200);
      t0 = now;
      while (u_system.u_core.u_regfile.a_regs[4] != 2 && now < t0 + 20000) @(negedge clk);
      if (u_system.u_core.u_regfile.a_regs[4] != 2) fail("NMIM=1 NMI handler did not run");
      else if (u_system.u_core.rf_sp !== sp0) fail($sformatf("NMIM=1 NMI moved SP %08h -> %08h", sp0, u_system.u_core.rf_sp));
      hw(HOST_REG_HSTCTL, HLT);                  // its RETI has nothing to return to
    end

    if (failures == 0) $display("TEST_RESULT: PASS (host load/readback, HLT release, 64 halts, 64 indirect accesses, NMI, INTIN, INTOUT, CF, LBL=1, NMIM=1)");
    else $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin
    #20_000_000;
    $display("TEST_RESULT: FAIL: tb_host_sys hard timeout");
    $fatal(1);
  end
endmodule : tb_host_sys
