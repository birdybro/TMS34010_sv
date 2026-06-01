// -----------------------------------------------------------------------------
// tb_mem_field.sv
//
// Unit test for the generalized bit-field path in sim_memory_model: reads and
// writes of 1..32 bits at arbitrary bit addresses, including fields that
// straddle 16-bit word boundaries, with read-modify-write preservation of the
// surrounding bits. This is the memory-model foundation for the TMS34010
// field-size (FS/FE) machinery; the core's existing aligned 16/32-bit accesses
// are the boff=0 special cases.
//
// Drives the request/ack protocol directly (no core): assert mem_req with the
// access fields, wait for the one-cycle mem_ack, sample mem_rdata on reads.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_mem_field;
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

  sim_memory_model #(.DEPTH_WORDS(64)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  int unsigned failures;

  // One field access over the request/ack protocol. For reads, `data`
  // returns the captured mem_rdata; for writes it is ignored.
  task automatic do_access(input  logic                    we,
                           input  logic [ADDR_WIDTH-1:0]   addr,
                           input  logic [FIELD_SIZE_WIDTH-1:0] size,
                           input  logic [DATA_WIDTH-1:0]   wdata,
                           output logic [DATA_WIDTH-1:0]   data);
    @(negedge clk);
    mem_req   = 1'b1;
    mem_we    = we;
    mem_addr  = addr;
    mem_size  = size;
    mem_wdata = wdata;
    do @(negedge clk); while (mem_ack !== 1'b1);
    data    = mem_rdata;
    mem_req = 1'b0;
    @(negedge clk);
  endtask

  task automatic do_write(input logic [ADDR_WIDTH-1:0] addr,
                          input logic [FIELD_SIZE_WIDTH-1:0] size,
                          input logic [DATA_WIDTH-1:0] wdata);
    logic [DATA_WIDTH-1:0] dummy;
    do_access(1'b1, addr, size, wdata, dummy);
  endtask

  task automatic check_read(input string label,
                            input logic [ADDR_WIDTH-1:0] addr,
                            input logic [FIELD_SIZE_WIDTH-1:0] size,
                            input logic [DATA_WIDTH-1:0] expected);
    logic [DATA_WIDTH-1:0] got;
    do_access(1'b0, addr, size, '0, got);
    if (got !== expected) begin
      $display("TEST_RESULT: FAIL: %s: addr=%0d size=%0d expected=%08h actual=%08h",
               label, addr, size, expected, got);
      failures++;
    end
  endtask

  task automatic check_word(input string label, input int unsigned widx,
                            input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned i;
    failures = 0;
    mem_req = 1'b0; mem_we = 1'b0; mem_addr = '0; mem_size = '0; mem_wdata = '0;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);

    // 1) Aligned 32-bit write then read (boff=0 special case still works).
    do_write(32'd0, 6'd32, 32'hDEAD_BEEF);   // bit addr 0 -> words 0,1
    check_word("1: mem[0] low",  0, 16'hBEEF);
    check_word("1: mem[1] high", 1, 16'hDEAD);
    check_read("1: read back 32", 32'd0, 6'd32, 32'hDEAD_BEEF);

    // 2) Aligned 16-bit read of a preloaded word.
    u_mem.mem[4] = 16'hABCD;                  // word 4 = bit addr 64
    check_read("2: 16b @ word4", 32'd64, 6'd16, 32'h0000_ABCD);

    // 3) Sub-field read inside one word: 4 bits at bit offset 4 of 0xABCD.
    //    (0xABCD >> 4) & 0xF = 0xC.
    check_read("3: 4b @ bit68", 32'd68, 6'd4, 32'h0000_000C);

    // 4) RMW preserves surrounding bits: clear the low nibble of word 4.
    //    Write 4 bits = 0x0 at bit addr 64 -> mem[4] = 0xABC0.
    do_write(32'd64, 6'd4, 32'h0000_0000);
    check_word("4: mem[4] low nibble cleared", 4, 16'hABC0);

    // 5) Field straddling a word boundary: write 9 bits = 0x1FF at bit
    //    addr 12 (boff=12, widx=0). Field spans word0 bits[15:12] and
    //    word1 bits[4:0]. First clear words 0/1.
    do_write(32'd0,  6'd32, 32'h0000_0000);
    do_write(32'd12, 6'd9,  32'h0000_01FF);
    //    word0[15:12]=1111 -> 0xF000; word1[4:0]=11111 -> 0x001F.
    check_word("5: mem[0] high nibble set", 0, 16'hF000);
    check_word("5: mem[1] low 5 bits set",  1, 16'h001F);
    check_read("5: read back 9b @ bit12", 32'd12, 6'd9, 32'h0000_01FF);
    //    Bits outside the field stay 0: read 12 bits at bit0 -> 0.
    check_read("5: below-field bits clear", 32'd0, 6'd12, 32'h0000_0000);

    // 6) 32-bit field at an unaligned offset (boff=8): spans words 2,3,4.
    //    Clear first, then write 0x12345678 at bit addr 40 (word2 bit8).
    do_write(32'd32, 6'd32, 32'h0000_0000);   // words 2,3
    do_write(32'd48, 6'd32, 32'h0000_0000);   // words 3,4
    do_write(32'd40, 6'd32, 32'h1234_5678);   // bit40: boff=8, widx=2
    check_read("6: read back 32b @ bit40", 32'd40, 6'd32, 32'h1234_5678);
    //    word2 should hold the low 8 bits of 0x5678 shifted up by 8: 0x7800.
    check_word("6: mem[2] = 0x7800", 2, 16'h7800);

    // 7) Single-bit write/read at an odd bit address.
    do_write(32'd80, 6'd16, 32'h0000_0000);   // word 5 cleared
    do_write(32'd87, 6'd1,  32'h0000_0001);   // set bit 7 of word 5
    check_word("7: mem[5] bit7 set", 5, 16'h0080);
    check_read("7: read bit87", 32'd87, 6'd1, 32'h0000_0001);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (sim_memory_model bit-field RMW: aligned, sub-word, straddling, single-bit)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_mem_field hard timeout");
    $fatal(1);
  end

endmodule : tb_mem_field
