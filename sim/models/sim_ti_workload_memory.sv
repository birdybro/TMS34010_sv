// Sparse two-window physical memory used only by the preserved TI workload
// replay.  Architectural field requests still pass through the production
// 16-bit field sequencer; the backing arrays cover the low framebuffer window
// and the high SDB program window without aliasing either address range.

module sim_ti_workload_memory
  import tms34010_pkg::*;
#(
  parameter int unsigned WINDOW_WORDS = 262144
)(
  input  logic                              clk,
  input  logic                              rst,
  input  logic                              mem_req,
  input  logic                              mem_we,
  input  logic [ADDR_WIDTH-1:0]             mem_addr,
  input  logic [FIELD_SIZE_WIDTH-1:0]       mem_size,
  input  logic [DATA_WIDTH-1:0]             mem_wdata,
  output logic [DATA_WIDTH-1:0]             mem_rdata,
  output logic                              mem_ack
);

  localparam logic [ADDR_WIDTH-1:0] LOW_LIMIT  = 32'h0040_0000;
  localparam logic [ADDR_WIDTH-1:0] HIGH_BASE  = 32'hFFC0_0000;

  local_word_t low_mem  [0:WINDOW_WORDS-1];
  local_word_t high_mem [0:WINDOW_WORDS-1];

  logic                              word_req;
  logic                              word_we;
  logic [ADDR_WIDTH-1:0]             word_addr;
  local_word_t                       word_wdata;
  local_word_t                       word_rdata;
  logic                              word_ack;

  tms34010_field_sequencer u_field_sequencer (
    .clk(clk), .rst(rst),
    .field_req_i(mem_req), .field_we_i(mem_we),
    .field_addr_i(mem_addr), .field_size_i(mem_size),
    .field_wdata_i(mem_wdata), .field_rdata_o(mem_rdata),
    .field_ack_o(mem_ack),
    .word_req_o(word_req), .word_we_o(word_we),
    .word_addr_o(word_addr), .word_wdata_o(word_wdata),
    .word_rdata_i(word_rdata), .word_ack_i(word_ack),
    .word_restart_i(1'b0), .word_rmw_lock_o()
  );

  typedef enum logic [1:0] {
    WORD_IDLE,
    WORD_ACK
  } word_state_t;

  word_state_t state_q;
  logic [ADDR_WIDTH-1:0] latched_addr_q;
  logic                  latched_we_q;
  local_word_t           latched_wdata_q;
  int unsigned           low_index;
  int unsigned           high_index;

  assign word_ack = (state_q == WORD_ACK);

  always_comb begin
    low_index = latched_addr_q >> LOCAL_WORD_ADDR_LSB;
    high_index = (latched_addr_q - HIGH_BASE) >> LOCAL_WORD_ADDR_LSB;
    word_rdata = '0;
    if ((latched_addr_q < LOW_LIMIT) && (low_index < WINDOW_WORDS))
      word_rdata = low_mem[low_index];
    else if ((latched_addr_q >= HIGH_BASE)
             && (high_index < WINDOW_WORDS))
      word_rdata = high_mem[high_index];
  end

  initial begin
    for (int unsigned index = 0; index < WINDOW_WORDS; index++) begin
      low_mem[index] = '0;
      high_mem[index] = '0;
    end
  end

  always @(posedge clk) begin
    if (rst) begin
      state_q <= WORD_IDLE;
      latched_addr_q <= '0;
      latched_we_q <= 1'b0;
      latched_wdata_q <= '0;
    end else begin
      unique case (state_q)
        WORD_IDLE: begin
          if (word_req) begin
            latched_addr_q <= word_addr;
            latched_we_q <= word_we;
            latched_wdata_q <= word_wdata;
            state_q <= WORD_ACK;
          end
        end
        WORD_ACK: begin
          if (latched_we_q) begin
            if ((latched_addr_q < LOW_LIMIT) && (low_index < WINDOW_WORDS))
              low_mem[low_index] <= latched_wdata_q;
            else if ((latched_addr_q >= HIGH_BASE)
                     && (high_index < WINDOW_WORDS))
              high_mem[high_index] <= latched_wdata_q;
          end
          state_q <= WORD_IDLE;
        end
        default: state_q <= WORD_IDLE;
      endcase
    end
  end

endmodule : sim_ti_workload_memory
