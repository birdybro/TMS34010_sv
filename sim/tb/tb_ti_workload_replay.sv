// Deterministic execution smoke test for preserved TI software.  The vector is
// generated offline from disk images already present in the pinned reference
// submodule; no extracted TI executable is checked into this repository.

`timescale 1ns/1ps

module tb_ti_workload_replay;
  import tms34010_pkg::*;

  localparam int unsigned WINDOW_WORDS = 262144;
  localparam logic [31:0] HIGH_BASE = 32'hFFC0_0000;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                        mem_req;
  logic                        mem_we;
  logic [ADDR_WIDTH-1:0]       mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0] mem_size;
  logic [DATA_WIDTH-1:0]       mem_wdata;
  logic                        mem_srt;
  logic [DATA_WIDTH-1:0]       mem_rdata;
  logic                        mem_ack;
  core_state_t                 state_w;
  logic [ADDR_WIDTH-1:0]       pc_w;
  instr_word_t                 instr_w;
  logic                        illegal_w;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1),
    .video_vsync_n_i(1'b1), .rst(rst), .vclk_rst_i(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_size(mem_size), .mem_wdata(mem_wdata), .mem_srt(mem_srt),
    .mem_iaq(), .mem_is_io(), .mem_io_we(), .mem_io_rdata(),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack), .state_o(state_w),
    .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w),
    .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1),
    .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0),
    .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00),
    .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(),
    .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(),
    .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i(1'b0), .host_mem_is_io_o(), .host_mem_io_rdata_o(),
    .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(),
    .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(),
    .video_hblank_o(), .video_vblank_o(), .video_blank_o(),
    .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(), .screen_refresh_org_o()
  );

  sim_ti_workload_memory #(.WINDOW_WORDS(WINDOW_WORDS)) u_mem (
    .clk(clk), .rst(rst), .mem_req(mem_req), .mem_we(mem_we),
    .mem_addr(mem_addr), .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  integer vector_file;
  integer capture_file;
  integer scan_count;
  integer case_count;
  integer failures;
  string token;
  string repo_root;
  string vector_path;

  task automatic require_scan(
      input integer actual, input integer wanted, input string label);
    if (actual != wanted) begin
      $display("TEST_RESULT: FAIL: parse %s returned %0d, expected %0d",
               label, actual, wanted);
      $fatal(1);
    end
  endtask

  task automatic require_token(
      input string actual, input string wanted, input string label);
    if (actual != wanted) begin
      $display("TEST_RESULT: FAIL: %s token '%s', expected '%s'",
               label, actual, wanted);
      $fatal(1);
    end
  endtask

  function automatic logic [63:0] hash_word(
      input logic [63:0] prior, input logic [15:0] value);
    logic [63:0] next_hash;
    next_hash = (prior ^ 64'(value[7:0])) * 64'h00000100000001B3;
    hash_word = (next_hash ^ 64'(value[15:8])) * 64'h00000100000001B3;
  endfunction

  function automatic logic [15:0] read_word(input logic [31:0] address);
    int unsigned index;
    if (address < 32'h0040_0000) begin
      index = address >> 4;
      read_word = u_mem.low_mem[index];
    end else if (address >= HIGH_BASE) begin
      index = (address - HIGH_BASE) >> 4;
      read_word = u_mem.high_mem[index];
    end else begin
      read_word = 16'h0000;
    end
  endfunction

  task automatic write_word(
      input logic [31:0] address, input logic [15:0] value);
    int unsigned index;
    if (address < 32'h0040_0000) begin
      index = address >> 4;
      u_mem.low_mem[index] = value;
    end else if (address >= HIGH_BASE) begin
      index = (address - HIGH_BASE) >> 4;
      u_mem.high_mem[index] = value;
    end else begin
      $display("TEST_RESULT: FAIL: load address %08h is outside memory", address);
      $fatal(1);
    end
  endtask

  initial begin : main
    logic [31:0] case_id;
    logic [31:0] entry;
    logic [31:0] checkpoint;
    logic [31:0] timeout_polls;
    logic [31:0] load_words;
    logic [31:0] watch_count;
    logic [31:0] address;
    logic [31:0] value;
    logic [31:0] watch_address;
    logic [31:0] watch_words;
    logic [63:0] watch_hash;
    string watch_name;
    logic reached_endpoint;
    logic aborted;
    logic [31:0] pc_history [0:31];
    int unsigned history_head;
    int unsigned history_count;

    failures = 0;
    if (!$value$plusargs("TMS34010_REPO_ROOT=%s", repo_root)) begin
      $display("TEST_RESULT: FAIL: missing TMS34010_REPO_ROOT plusarg");
      $finish;
    end
    vector_path = {repo_root, "/work/ti_workloads/ti_workload_vectors.txt"};
    vector_file = $fopen(vector_path, "r");
    capture_file = $fopen(
        {repo_root, "/work/rtl_ti_workload_actual.txt"}, "w");
    if ((vector_file == 0) || (capture_file == 0)) begin
      $display("TEST_RESULT: FAIL: generated TI workload vector is unavailable");
      $finish;
    end
    scan_count = $fscanf(vector_file, "%s %h", token, case_count);
    require_scan(scan_count, 2, "vector header");
    require_token(token, "TMS34010_TI_WORKLOADS_V1", "vector header");
    $fdisplay(capture_file, "TMS34010_TI_RESULTS_V1 %0h", case_count);

    for (int unsigned case_index = 0;
         case_index < int'(case_count); case_index++) begin
      @(negedge clk);
      rst = 1'b1;
      repeat (3) @(posedge clk);
      #1;
      for (int unsigned index = 0; index < WINDOW_WORDS; index++) begin
        u_mem.low_mem[index] = 16'h0000;
        u_mem.high_mem[index] = 16'h0000;
      end

      scan_count = $fscanf(vector_file, "%s %h %h %h %h %h %h",
                           token, case_id, entry, checkpoint, timeout_polls,
                           load_words, watch_count);
      require_scan(scan_count, 7, "CASE");
      require_token(token, "CASE", "case");
      scan_count = $fscanf(vector_file, "%s", token);
      require_scan(scan_count, 1, "LOAD");
      require_token(token, "LOAD", "load");
      for (int unsigned word = 0; word < int'(load_words); word++) begin
        scan_count = $fscanf(vector_file, "%h %h", address, value);
        require_scan(scan_count, 2, "load word");
        write_word(address, value[15:0]);
      end
      // Every selected executable is started through the architectural
      // level-zero reset vector, including those normally loaded by SDBL.
      write_word(RESET_VECTOR_ADDR, entry[15:0]);
      write_word(RESET_VECTOR_ADDR + 16, entry[31:16]);

      @(negedge clk);
      rst = 1'b0;
      reached_endpoint = 1'b0;
      aborted = 1'b0;
      history_head = 0;
      history_count = 0;
      begin : wait_for_endpoint
        for (int unsigned cycle = 0;
             cycle < int'(timeout_polls) * 500; cycle++) begin
          @(posedge clk);
          #1;
          if (state_w == CORE_FETCH) begin
            pc_history[history_head] = pc_w;
            history_head = (history_head + 1) % 32;
            if (history_count < 32)
              history_count++;
          end
          if ((state_w == CORE_FETCH) && (pc_w == checkpoint)) begin
            reached_endpoint = 1'b1;
            disable wait_for_endpoint;
          end
          if (illegal_w) begin
            $display(
                "TEST_RESULT: FAIL: case %08h illegal opcode %04h at PC=%08h",
                case_id, instr_w, pc_w);
            $write("  recent fetch PCs:");
            for (int unsigned item = 0; item < history_count; item++)
              $write(" %08h", pc_history[
                  (history_head + 32 - history_count + item) % 32]);
            $write("\n");
            failures++;
            aborted = 1'b1;
            disable wait_for_endpoint;
          end
        end
      end
      if (!reached_endpoint && !aborted) begin
        $display(
            "TEST_RESULT: FAIL: case %08h timeout PC=%08h state=%0d instruction=%04h",
            case_id, pc_w, state_w, instr_w);
        failures++;
      end

      $fdisplay(capture_file, "CASE %08h %08h %08h %08h",
                case_id, pc_w, u_core.u_regfile.sp_q,
                u_core.u_status_reg.st_q);
      $fwrite(capture_file, "A");
      for (int unsigned index = 0; index < 15; index++)
        $fwrite(capture_file, " %08h", u_core.u_regfile.a_regs[index]);
      $fwrite(capture_file, "\nB");
      for (int unsigned index = 0; index < 15; index++)
        $fwrite(capture_file, " %08h", u_core.u_regfile.b_regs[index]);
      $fwrite(capture_file, "\nIO");
      $fwrite(capture_file, " %04h", u_core.u_io_regs.io_reg[IO_IDX_DPYCTL]);
      $fwrite(capture_file, " %04h", u_core.u_io_regs.io_reg[IO_IDX_CONTROL]);
      $fwrite(capture_file, " %04h", u_core.u_io_regs.io_reg[IO_IDX_CONVSP]);
      $fwrite(capture_file, " %04h", u_core.u_io_regs.io_reg[IO_IDX_CONVDP]);
      $fwrite(capture_file, " %04h", u_core.u_io_regs.io_reg[IO_IDX_PSIZE]);
      $fwrite(capture_file, " %04h", u_core.u_io_regs.io_reg[IO_IDX_PMASK]);
      $fwrite(capture_file, "\n");

      for (int unsigned watch = 0;
           watch < int'(watch_count); watch++) begin
        scan_count = $fscanf(vector_file, "%s %s %h %h",
                             token, watch_name, watch_address, watch_words);
        require_scan(scan_count, 4, "WATCH");
        require_token(token, "WATCH", "watch");
        watch_hash = 64'hCBF29CE484222325;
        for (int unsigned word = 0; word < int'(watch_words); word++)
          watch_hash = hash_word(
              watch_hash, read_word(watch_address + word * 16));
        $fdisplay(capture_file, "HASH %s %016h", watch_name, watch_hash);
      end
      scan_count = $fscanf(vector_file, "%s", token);
      require_scan(scan_count, 1, "END");
      require_token(token, "END", "case end");
      $fdisplay(capture_file, "END");
    end

    $fclose(vector_file);
    $fclose(capture_file);
    if (failures == 0)
      $display("TEST_RESULT: PASS (%0d preserved TI workloads reached deterministic checkpoints)",
               case_count);
    else
      $display("TEST_RESULT: FAIL: %0d workload failure(s)", failures);
    $finish;
  end

  initial begin : watchdog
    #2_000_000_000;
    $display("TEST_RESULT: FAIL: tb_ti_workload_replay hard timeout");
    $fatal(1);
  end

endmodule : tb_ti_workload_replay
