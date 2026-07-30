// -----------------------------------------------------------------------------
// Offline replay of the deterministic graphics corpus accepted from the exact
// pinned MAME revision.  Both text files are checked in; no network access or
// MAME installation is needed by the ordinary regression.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mame_graphics_replay;
  import tms34010_pkg::*;

  localparam int unsigned MEM_WORDS = 16384;
  localparam int unsigned MAX_WATCH_WORDS = 512;
  localparam logic [15:0] LOOP_OPCODE = 16'hC0FF;
  localparam logic [15:0] DONE_PREFIX = 16'hD172;

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

  sim_memory_model #(
    .DEPTH_WORDS(MEM_WORDS),
    .WORD_WAIT_CYCLES(1)
  ) u_mem (
    .clk(clk), .rst(rst), .mem_req(mem_req), .mem_we(mem_we),
    .mem_addr(mem_addr), .mem_size(mem_size), .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  logic [31:0] expected_a [0:14];
  logic [31:0] expected_b [0:14];
  logic [15:0] expected_io [0:5];
  logic [15:0] expected_mem [0:MAX_WATCH_WORDS-1];

  integer vector_file;
  integer expected_file;
  integer scan_count;
  integer case_count;
  integer expected_count;
  integer failures;
  integer capture_file;
  string token;
  string repo_root;
  string vector_path;
  string expected_path;

  task automatic require_scan(input integer actual, input integer wanted,
                              input string label);
    if (actual != wanted) begin
      $display("TEST_RESULT: FAIL: parse %s returned %0d, expected %0d",
               label, actual, wanted);
      $fatal(1);
    end
  endtask

  task automatic require_token(input string actual, input string wanted,
                               input string label);
    if (actual != wanted) begin
      $display("TEST_RESULT: FAIL: %s token '%s', expected '%s'",
               label, actual, wanted);
      $fatal(1);
    end
  endtask

  initial begin : main
    logic [31:0] case_id;
    logic [31:0] expected_id;
    logic [31:0] program_words;
    logic [31:0] memory_words;
    logic [31:0] watch_base;
    logic [31:0] watch_words;
    logic [31:0] address;
    logic [31:0] word_value;
    logic [31:0] expected_pc;
    logic [31:0] expected_sp;
    logic [31:0] expected_st;
    logic reached_endpoint;

    failures = 0;
    if (!$value$plusargs("TMS34010_REPO_ROOT=%s", repo_root)) begin
      $display("TEST_RESULT: FAIL: missing TMS34010_REPO_ROOT plusarg");
      $finish;
    end
    vector_path = {repo_root, "/sim/vectors/mame_graphics_vectors.txt"};
    expected_path = {repo_root, "/sim/vectors/mame_graphics_expected.txt"};
    vector_file = $fopen(vector_path, "r");
    expected_file = $fopen(expected_path, "r");
    capture_file = $fopen(
        {repo_root, "/work/rtl_graphics_actual.txt"}, "w");
    if ((vector_file == 0) || (expected_file == 0)) begin
      $display("TEST_RESULT: FAIL: cannot open checked-in MAME vectors");
      $finish;
    end

    scan_count = $fscanf(vector_file, "%s %h", token, case_count);
    require_scan(scan_count, 2, "vector header");
    require_token(token, "TMS34010_GRAPHICS_V1", "vector header");
    scan_count = $fscanf(expected_file, "%s %h", token, expected_count);
    require_scan(scan_count, 2, "result header");
    require_token(token, "TMS34010_GRAPHICS_RESULTS_V1", "result header");
    if (case_count != expected_count) begin
      $display("TEST_RESULT: FAIL: corpus count %0d/%0d",
               case_count, expected_count);
      $finish;
    end
    if (capture_file == 0) begin
      $display("TEST_RESULT: FAIL: cannot open RTL capture output");
      $finish;
    end
    $fdisplay(capture_file, "TMS34010_GRAPHICS_RESULTS_V1 %0h",
              case_count);

    for (int unsigned case_index = 0;
         case_index < int'(case_count); case_index++) begin
      @(negedge clk);
      rst = 1'b1;
      repeat (3) @(posedge clk);
      #1;
      for (int unsigned index = 0; index < MEM_WORDS; index++)
        u_mem.mem[index] = 16'h0000;

      scan_count = $fscanf(vector_file, "%s %h %h %h %h %h",
                           token, case_id, program_words, memory_words,
                           watch_base, watch_words);
      require_scan(scan_count, 6, "CASE");
      require_token(token, "CASE", "vector case");
      if (watch_words > MAX_WATCH_WORDS) begin
        $display("TEST_RESULT: FAIL: case %0d watch size %0d",
                 case_index, watch_words);
        $finish;
      end
      scan_count = $fscanf(vector_file, "%s", token);
      require_scan(scan_count, 1, "PROGRAM");
      require_token(token, "PROGRAM", "program");
      for (int unsigned index = 0;
           index < int'(program_words); index++) begin
        scan_count = $fscanf(vector_file, "%h", word_value);
        require_scan(scan_count, 1, "program word");
        u_mem.mem[index] = word_value[15:0];
      end
      scan_count = $fscanf(vector_file, "%s", token);
      require_scan(scan_count, 1, "MEMORY");
      require_token(token, "MEMORY", "memory");
      for (int unsigned index = 0;
           index < int'(memory_words); index++) begin
        scan_count = $fscanf(vector_file, "%h %h", address, word_value);
        require_scan(scan_count, 2, "memory pair");
        u_mem.mem[address] = word_value[15:0];
      end
      scan_count = $fscanf(vector_file, "%s", token);
      require_scan(scan_count, 1, "END");
      require_token(token, "END", "vector end");

      scan_count = $fscanf(expected_file, "%s %h %h %h %h",
                           token, expected_id, expected_pc,
                           expected_sp, expected_st);
      require_scan(scan_count, 5, "expected CASE");
      require_token(token, "CASE", "expected case");
      if (expected_id != case_id) begin
        $display("TEST_RESULT: FAIL: case id %08h/%08h",
                 case_id, expected_id);
        $finish;
      end
      scan_count = $fscanf(expected_file, "%s", token);
      require_scan(scan_count, 1, "expected A");
      require_token(token, "A", "expected A");
      for (int unsigned index = 0; index < 15; index++) begin
        scan_count = $fscanf(expected_file, "%h", expected_a[index]);
        require_scan(scan_count, 1, "expected A register");
      end
      scan_count = $fscanf(expected_file, "%s", token);
      require_scan(scan_count, 1, "expected B");
      require_token(token, "B", "expected B");
      for (int unsigned index = 0; index < 15; index++) begin
        scan_count = $fscanf(expected_file, "%h", expected_b[index]);
        require_scan(scan_count, 1, "expected B register");
      end
      scan_count = $fscanf(expected_file, "%s", token);
      require_scan(scan_count, 1, "expected IO");
      require_token(token, "IO", "expected IO");
      for (int unsigned index = 0; index < 6; index++) begin
        scan_count = $fscanf(expected_file, "%h", expected_io[index]);
        require_scan(scan_count, 1, "expected IO register");
      end
      scan_count = $fscanf(expected_file, "%s", token);
      require_scan(scan_count, 1, "expected MEM");
      require_token(token, "MEM", "expected memory");
      for (int unsigned index = 0;
           index < int'(watch_words); index++) begin
        scan_count = $fscanf(expected_file, "%h", expected_mem[index]);
        require_scan(scan_count, 1, "expected memory word");
      end
      scan_count = $fscanf(expected_file, "%s", token);
      require_scan(scan_count, 1, "expected END");
      require_token(token, "END", "expected end");

      @(negedge clk);
      rst = 1'b0;
      reached_endpoint = 1'b0;
      begin : wait_for_endpoint
        for (int unsigned cycle = 0; cycle < 20000; cycle++) begin
          @(posedge clk);
          #1;
          if ((u_core.u_regfile.a_regs[14][31:16] == DONE_PREFIX)
              && (state_w == CORE_EXECUTE) && (instr_w == LOOP_OPCODE)) begin
            reached_endpoint = 1'b1;
            disable wait_for_endpoint;
          end
        end
      end
      if (!reached_endpoint) begin
        $display("TEST_RESULT: FAIL: case %0d/%08h timeout PC=%08h state=%0d instruction=%04h illegal=%0b",
                 case_index, case_id, pc_w, state_w, instr_w, illegal_w);
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
      $fdisplay(capture_file, "");
      $fdisplay(capture_file, "IO %04h %04h %04h %04h %04h %04h",
                u_core.u_io_regs.io_reg[IO_IDX_DPYCTL],
                u_core.u_io_regs.io_reg[IO_IDX_CONTROL],
                u_core.u_io_regs.io_reg[IO_IDX_CONVSP],
                u_core.u_io_regs.io_reg[IO_IDX_CONVDP],
                u_core.u_io_regs.io_reg[IO_IDX_PSIZE],
                u_core.u_io_regs.io_reg[IO_IDX_PMASK]);
      $fwrite(capture_file, "MEM");
      for (int unsigned index = 0;
           index < int'(watch_words); index++)
        $fwrite(capture_file, " %04h", u_mem.mem[watch_base + index]);
      $fdisplay(capture_file, "\nEND");

      if ((pc_w !== expected_pc)
          || (u_core.u_regfile.sp_q !== expected_sp)
          || (u_core.u_status_reg.st_q !== expected_st)) begin
        $display("TEST_RESULT: FAIL: case %0d state PC=%08h/%08h SP=%08h/%08h ST=%08h/%08h",
                 case_index, pc_w, expected_pc,
                 u_core.u_regfile.sp_q, expected_sp,
                 u_core.u_status_reg.st_q, expected_st);
        failures++;
      end
      for (int unsigned index = 0; index < 15; index++) begin
        if (u_core.u_regfile.a_regs[index] !== expected_a[index]) begin
          $display("TEST_RESULT: FAIL: case %0d A%0d=%08h/%08h",
                   case_index, index, u_core.u_regfile.a_regs[index],
                   expected_a[index]);
          failures++;
        end
        if (u_core.u_regfile.b_regs[index] !== expected_b[index]) begin
          $display("TEST_RESULT: FAIL: case %0d B%0d=%08h/%08h",
                   case_index, index, u_core.u_regfile.b_regs[index],
                   expected_b[index]);
          failures++;
        end
      end
      if ((u_core.u_io_regs.io_reg[IO_IDX_DPYCTL] !== expected_io[0])
          || (u_core.u_io_regs.io_reg[IO_IDX_CONTROL] !== expected_io[1])
          || (u_core.u_io_regs.io_reg[IO_IDX_CONVSP] !== expected_io[2])
          || (u_core.u_io_regs.io_reg[IO_IDX_CONVDP] !== expected_io[3])
          || (u_core.u_io_regs.io_reg[IO_IDX_PSIZE] !== expected_io[4])
          || (u_core.u_io_regs.io_reg[IO_IDX_PMASK] !== expected_io[5])) begin
        $display("TEST_RESULT: FAIL: case %0d graphics I/O mismatch",
                 case_index);
        failures++;
      end
      for (int unsigned index = 0;
           index < int'(watch_words); index++) begin
        if (u_mem.mem[watch_base + index] !== expected_mem[index]) begin
          $display("TEST_RESULT: FAIL: case %0d memory[%0h]=%04h/%04h",
                   case_index, watch_base + index,
                   u_mem.mem[watch_base + index], expected_mem[index]);
          failures++;
        end
      end
      if (illegal_w) begin
        $display("TEST_RESULT: FAIL: case %0d illegal opcode", case_index);
        failures++;
      end
    end

    $fclose(vector_file);
    $fclose(expected_file);
    $fclose(capture_file);
    if (failures == 0)
      $display("TEST_RESULT: PASS (%0d checked-in pinned-MAME graphics replays)",
               case_count);
    else
      $display("TEST_RESULT: FAIL (%0d mismatches)", failures);
    $finish;
  end
endmodule
