// -----------------------------------------------------------------------------
// tb_accuracy.sv
//
// Instruction-timing bench. Reads the runs written by tools/accuracy/cases.py,
// runs each from reset through tms34010_system, and reports the core clocks
// each instruction under test takes against the TMS34010 User's Guide
// (SPVU001A, 1988) machine states x CLKS_PER_STATE.
//
// The memory target models zero-wait local memory: every word cycle is
// acknowledged ACK_DELAY clocks after the bench first sees it.
//
// Measured per run (second pass of the case's loop):
//   clocks  - from the end of the test instruction's opcode fetch (PC = T) to
//             the end of the next instruction's opcode fetch (PC = N);
//   quiet   - from the same start to the last write cycle acknowledged
//             before the loop's closing DSJS starts (0 if none).
// Output lines: "RUN <id> <name> <page> <cd> <exp_states> <exp_hidden>
// <clocks> <quiet>". tools/accuracy/report.py turns them into the table.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_accuracy;
  import tms34010_pkg::*;

  parameter int unsigned ACK_DELAY = 16;
  parameter bit          CYCLE_ACCURATE = 1'b0;
  parameter int unsigned CLKS_PER_STATE = 8;
  parameter int unsigned TIMEOUT   = 200000;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #1 clk = ~clk;

  logic                      cycle_req;
  local_cycle_kind_t         cycle_kind;
  logic [ADDR_WIDTH-1:0]     cycle_addr;
  local_word_t               cycle_wdata;
  local_word_t               cycle_io_rdata;
  logic                      cycle_iaq;
  local_word_t               cycle_rdata;
  logic                      cycle_ack;
  core_state_t               core_state;

  // Host traffic (+HOSTPER=<n>): a host read of HSTDATA every n clocks, which
  // puts bus cycles off the state grid. 0 (default): no host traffic.
  logic            host_req = 1'b0;
  logic            host_ack;
  int              host_per;
  longint unsigned host_clk = 0;
  initial if (!$value$plusargs("HOSTPER=%d", host_per)) host_per = 0;
  always @(posedge clk) begin
    host_clk <= host_clk + 1;
    if (rst || host_per == 0)            host_req <= 1'b0;
    else if (host_ack)                   host_req <= 1'b0;
    else if (host_clk % host_per == 0)   host_req <= 1'b1;
  end

  // Bus hold (+HOLDPER=<n> +HOLDLEN=<m>): every n clocks request HOLD and keep
  // it m clocks after HLDA. 0 (default): no hold.
  logic            hold_req = 1'b0;
  logic            hold_ack;
  int              hold_per, hold_len, hold_cnt = 0;
  initial begin
    if (!$value$plusargs("HOLDPER=%d", hold_per)) hold_per = 0;
    if (!$value$plusargs("HOLDLEN=%d", hold_len)) hold_len = 16;
  end
  always @(posedge clk) begin
    if (rst || hold_per == 0) begin
      hold_req <= 1'b0;
      hold_cnt <= 0;
    end else if (hold_req) begin
      if (hold_ack) hold_cnt <= hold_cnt + 1;
      if (hold_ack && hold_cnt + 1 >= hold_len) begin
        hold_req <= 1'b0;
        hold_cnt <= 0;
      end
    end else if (host_clk % hold_per == 0) begin
      hold_req <= 1'b1;
    end
  end
  logic [ADDR_WIDTH-1:0]     pc;

  tms34010_system #(
    .CLKS_PER_STATE (CLKS_PER_STATE),
    .CYCLE_ACCURATE (CYCLE_ACCURATE)
  ) u_system (
    .clk               (clk), .vclk_i(clk),
    .rst               (rst), .vclk_rst_i(rst),
    .video_hsync_n_i   (1'b1),
    .video_vsync_n_i   (1'b1),
    .run_emu_n_i       (1'b1),
    .emua_n_o          (),
    .hcs_n_i           (1'b0),
    .host_req_i        (host_req),
    .host_we_i         (1'b0),
    .host_reg_i        (HOST_REG_HSTDATA),
    .host_be_i         (2'b11),
    .host_wdata_i      (16'h0000),
    .host_rdata_o      (),
    .host_ack_o        (host_ack),
    .host_busy_o       (),
    .hint_n_o          (),
    .lint1_n_i         (lint1_n),
    .lint2_n_i         (1'b1),
    .dpyint_set_i      (1'b0),
    .hold_req_i        (hold_req),
    .hold_ack_o        (hold_ack),
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
    .cycle_srfaddr_o   (),
    .cycle_dpytap_o    (),
    .cycle_screen_org_o(),
    .cycle_dram_row_o  (),
    .cycle_rdata_i     (cycle_rdata),
    .cycle_ack_i       (cycle_ack),
    .state_o           (core_state),
    .pc_o              (pc),
    .instr_word_o      (),
    .illegal_opcode_o  ()
  );

  // +INTAT=<n> +INTLEN=<m>: pull LINT1 low m clocks long, n clocks after the
  // measured instruction starts on its second pass (interrupt-resume checks).
  logic lint1_n;
  bit   no_stack;
  initial no_stack = $test$plusargs("NOSTACK");
  int   int_at, int_len;
  initial begin
    if (!$value$plusargs("INTAT=%d", int_at))  int_at  = -1;
    if (!$value$plusargs("INTLEN=%d", int_len)) int_len = 64;
  end

  // ------------------------------------------------------------ memory ---
  local_word_t mem [int unsigned];
  logic [31:0] reset_vector;

  typedef enum logic [1:0] {T_IDLE, T_BUSY, T_ACK} tstate_t;
  tstate_t                t_state;
  int unsigned            t_count;
  local_cycle_kind_t      t_kind;
  logic [ADDR_WIDTH-1:0]  t_addr;
  local_word_t            t_wdata;
  local_word_t            t_io_rdata;

  function automatic local_word_t read_word(logic [ADDR_WIDTH-1:0] a);
    int unsigned w = a >> 4;
    if (a == RESET_VECTOR_ADDR)        return reset_vector[15:0];
    if (a == RESET_VECTOR_ADDR + 16)   return reset_vector[31:16];
    if (mem.exists(w))                 return mem[w];
    return 16'h0000;
  endfunction

  assign cycle_ack   = (t_state == T_ACK);
  assign cycle_rdata = (t_kind == LOCAL_CYCLE_IO_READ) ? t_io_rdata : read_word(t_addr);

  always @(posedge clk) begin
    if (rst) begin
      t_state <= T_IDLE;
      t_count <= 0;
    end else begin
      case (t_state)
        T_IDLE: if (cycle_req) begin
          t_kind     <= cycle_kind;
          t_addr     <= cycle_addr;
          t_wdata    <= cycle_wdata;
          t_io_rdata <= cycle_io_rdata;
          t_count    <= 1;
          t_state    <= (ACK_DELAY <= 1) ? T_ACK : T_BUSY;
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

  // +TRACE prints one line per clock (use with +ONLY=<run id>).
  bit trace_on;
  initial trace_on = $test$plusargs("TRACE");
  always @(posedge clk) if (trace_on && !rst)
    $display("T %0d st=%0d pc=%08h req=%b we=%b ack=%b a=%08h | fab=%b | bus req=%b k=%0d ack=%b xack=%b | rel=%b sp=%08h iw=%04h",
             now, core_state, pc, u_system.u_core.mem_req, u_system.u_core.mem_we,
             u_system.u_core.mem_ack, u_system.u_core.mem_addr,
             u_system.u_memory_fabric.cpu_request_active_q,
             cycle_req, cycle_kind, u_system.u_memory_fabric.timed_ack, cycle_ack,
             u_system.u_core.pace_hold, u_system.u_core.rf_sp, u_system.u_core.instr_word_q);

  // ----------------------------------------------------------- monitor ---
  longint unsigned now;
  always @(posedge clk) now <= rst ? 0 : now + 1;

  logic [31:0] m_t, m_n, m_e;
  int unsigned seen_t;
  longint unsigned t_start, t_next, t_lastwr;
  localparam int HIDDEN_WINDOW = 11;
  bit          got_next, got_end;
  core_state_t prev_state;

  always @(posedge clk)
    lint1_n <= !(int_at >= 0 && seen_t >= 2 && !rst
                 && now >= t_start + longint'(int_at)
                 && now <  t_start + longint'(int_at) + longint'(int_len));

  always @(posedge clk) begin
    prev_state <= core_state;
    if (rst) begin
      seen_t   <= 0;
      got_next <= 0;
      got_end  <= 0;
      t_lastwr <= 0;
    end else begin
      // An instruction starts when its opcode fetch completes: the core
      // leaves CORE_FETCH for CORE_DECODE with PC already advanced past the
      // opcode. TI counts each instruction from there (13.1: the cache-off
      // figure = cache-hit + hidden states + 3 per instruction word, so an
      // instruction carries the next opcode fetch, not its own).
      if (prev_state == CORE_FETCH && core_state == CORE_DECODE) begin
        if (pc - 32'd16 == m_t) begin
          seen_t  <= seen_t + 1;
          if (seen_t == 1) t_start <= now;
        end
        // (An interrupted FILL is fetched again after RETI: with +INTAT the
        // measured pass may see T more than once.)
        if ((seen_t == 2 || (int_at >= 0 && seen_t > 2)) && !got_next && pc - 32'd16 == m_n) begin
          t_next   <= now;
          got_next <= 1;
        end
        if (seen_t >= 2 && got_next && !got_end && pc - 32'd16 == m_e) got_end <= 1;
      end
      // A write's bus time ends when the memory fabric's bus timer (or, with
      // CYCLE_ACCURATE=0, the target) acknowledges it.
      // Count every data cycle (reads of a read-modify-write too) of the
      // measured instruction: those before the next opcode fetch completes
      // and, after it, those within HIDDEN_WINDOW states (longer than any
      // hidden figure in the guide, and shorter than the drain NOPs that
      // follow every measured instruction, which are cache hits with no
      // data access).
      if (seen_t == 2 && !got_end && u_system.u_memory_fabric.timed_ack
          && (!got_next || now < t_next + HIDDEN_WINDOW * CLKS_PER_STATE)
          && (cycle_kind == LOCAL_CYCLE_WORD_WRITE || cycle_kind == LOCAL_CYCLE_PIXEL_RTM
              || cycle_kind == LOCAL_CYCLE_PIXEL_MTR
              || (cycle_kind == LOCAL_CYCLE_WORD_READ && !cycle_iaq)))
        t_lastwr <= now + 1;
    end
  end

  // A checksum of the data written below the code (word address and value of
  // every non-zero word outside the program; an unwritten word reads 0), so
  // pixel results can be compared between CYCLE_ACCURATE=1 and 0.
  function automatic logic [31:0] data_sum();
    logic [31:0] h = 32'h811C9DC5;
    foreach (mem[w]) begin
      if ((w < (32'h0010_0000 >> 4) || w >= (32'h0020_0000 >> 4)) && mem[w] != '0
          && !(no_stack && w >= (32'h002F_0000 >> 4) && w <= (32'h0030_0000 >> 4))) begin
        h = (h ^ w) * 32'h0100_0193;
        h = (h ^ {16'd0, mem[w]}) * 32'h0100_0193;
      end
    end
    return h;
  endfunction

  // -------------------------------------------------------------- runner --
  initial begin
    int fd, n, id, cd, exp_states, exp_hidden, nwords;
    int unsigned t_addr_i, n_addr_i, done_addr, sp, base, w;
    string kw, name, page, root, path;
    int runs, only;
    runs = 0;
    if (!$value$plusargs("ONLY=%d", only)) only = -1;
    if (!$value$plusargs("CASES=%s", path)) path = "work/accuracy_cases.txt";
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("TEST_RESULT: FAIL cannot open %s", path);
      $finish;
    end
    forever begin
      n = $fscanf(fd, "%s", kw);
      if (n != 1 || kw == "end") break;
      n = $fscanf(fd, "%d %s %s %d %d %d %h %h %h %h %d %h", id, name, page, cd,
                  exp_states, exp_hidden, t_addr_i, n_addr_i, done_addr, sp, nwords, base);
      mem.delete();
      for (int i = 0; i < nwords; i++) begin
        n = $fscanf(fd, "%h", w);
        mem[(base >> 4) + i] = w[15:0];
      end
      if (only >= 0 && id != only) continue;
      reset_vector = base;
      m_t = t_addr_i;
      m_n = n_addr_i;
      m_e = done_addr;
      rst = 1'b1;
      repeat (8) @(posedge clk);
      rst = 1'b0;
      for (int c = 0; c < TIMEOUT && !got_end; c++) @(posedge clk);
      @(posedge clk);
      if (!got_end)
        $display("RUN %0d %s %s %0d %0d %0d TIMEOUT seen=%0d pc=%08h", id, name, page, cd,
                 exp_states, exp_hidden, seen_t, pc);
      else
        $display("RUN %0d %s %s %0d %0d %0d %0d %0d A0=%08h A1=%08h A2=%08h A3=%08h B0=%08h B2=%08h B7=%08h B10=%08h ST=%08h MEM=%08h",
                 id, name, page, cd, exp_states, exp_hidden, t_next - t_start,
                 // hidden states: from the start of the state in which the
                 // next opcode fetch completed (now and the core's state
                 // phase both count from reset)
                 (t_lastwr > t_next - t_next % CLKS_PER_STATE)
                   ? t_lastwr - (t_next - t_next % CLKS_PER_STATE) : 0,
                 u_system.u_core.u_regfile.a_regs[0], u_system.u_core.u_regfile.a_regs[1],
                 u_system.u_core.u_regfile.a_regs[2], u_system.u_core.u_regfile.a_regs[3],
                 u_system.u_core.u_regfile.b_regs[0], u_system.u_core.u_regfile.b_regs[2],
                 u_system.u_core.u_regfile.b_regs[7], u_system.u_core.u_regfile.b_regs[10],
                 u_system.u_core.st_value, data_sum());
      runs++;
    end
    $fclose(fd);
    $display("accuracy runs: %0d", runs);
    $display("TEST_RESULT: PASS");
    $finish;
  end

  // Bus log (+BUSLOG): the clock each external cycle starts, for comparing
  // two versions cycle by cycle (tools/accuracy/buscmp.py).
  bit              bus_log;
  longint unsigned bus_clk;
  logic            bus_open;
  initial bus_log = $test$plusargs("BUSLOG");
  always @(posedge clk) begin
    bus_clk  <= rst ? 0 : bus_clk + 1;
    bus_open <= rst ? 1'b0 : (cycle_req && !cycle_ack);
    if (bus_log && !rst && cycle_req && !bus_open)
      $display("BUS c=%0d k=%0d a=%08h w=%04h", bus_clk, cycle_kind, cycle_addr, cycle_wdata);
  end
endmodule
