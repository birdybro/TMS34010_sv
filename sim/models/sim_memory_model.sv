// -----------------------------------------------------------------------------
// sim_memory_model.sv
//
// Behavioral memory target for testbenches. NOT synthesizable.
//
// The public interface is the core's architectural field request/acknowledge
// boundary: one 1..32-bit access at any bit address. Unlike the original
// atomic behavioral splice, this model now routes every request through the
// synthesizable tms34010_field_sequencer. Its backing target accepts only
// aligned 16-bit physical words, so every core-level regression exercises
// the exact one-, two-, and three-word extraction and insertion phasing from
// the 1988 User's Guide §4.1.
//
// Public testbench API:
//   - `mem[0:DEPTH_WORDS-1]` is the 16-bit physical backing store.
//   - `level0_vector` models the full-address RESET/TRAP-0 vector without
//     aliasing it into the bounded low-memory array.
//
// Protocol:
//
//        clk        __/¯¯\__/¯¯\__/¯¯\__/¯¯\__/¯¯\__
//        mem_req    _______/¯¯¯¯¯¯¯¯¯¯¯¯¯\________   held until final ack
//        mem_ack    __________________/¯¯\_________   one-cycle field response
//        mem_rdata  ..................XdataX.......   valid with mem_ack
//
// Individual physical word requests use the same request/ack contract and
// receive one-cycle target latency. This model deliberately does not add
// random waits; tb_field_sequencer provides stalled-word coverage.
// -----------------------------------------------------------------------------

module sim_memory_model
  import tms34010_pkg::*;
#(
  parameter int unsigned DEPTH_WORDS = 1024,
  parameter logic [DATA_WIDTH-1:0] LEVEL0_VECTOR_INIT = '0
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

  localparam int unsigned IDX_WIDTH = $clog2(DEPTH_WORDS);
  localparam logic [ADDR_WIDTH-1:0] LEVEL0_VECTOR_HIGH_ADDR =
      RESET_VECTOR_ADDR + ADDR_WIDTH'(LOCAL_WORD_WIDTH);

  // Physical backing store, intentionally public for deterministic test setup.
  local_word_t mem [0:DEPTH_WORDS-1];
  logic [DATA_WIDTH-1:0] level0_vector;

  logic                  word_req;
  logic                  word_we;
  logic [ADDR_WIDTH-1:0] word_addr;
  local_word_t           word_wdata;
  local_word_t           word_rdata;
  logic                  word_ack;

  tms34010_field_sequencer u_field_sequencer (
    .clk             (clk),
    .rst             (rst),
    .field_req_i     (mem_req),
    .field_we_i      (mem_we),
    .field_addr_i    (mem_addr),
    .field_size_i    (mem_size),
    .field_wdata_i   (mem_wdata),
    .field_rdata_o   (mem_rdata),
    .field_ack_o     (mem_ack),
    .word_req_o      (word_req),
    .word_we_o       (word_we),
    .word_addr_o     (word_addr),
    .word_wdata_o    (word_wdata),
    .word_rdata_i    (word_rdata),
    .word_ack_i      (word_ack),
    .word_rmw_lock_o ()
  );

  typedef enum logic [0:0] {
    WORD_IDLE = 1'b0,
    WORD_ACK  = 1'b1
  } word_state_t;

  word_state_t state_q;
  logic [ADDR_WIDTH-1:0] latched_word_addr_q;
  logic                  latched_word_we_q;
  local_word_t           latched_word_wdata_q;

  logic [IDX_WIDTH-1:0] word_index;
  assign word_index =
      latched_word_addr_q[IDX_WIDTH+LOCAL_WORD_ADDR_LSB-1
                          : LOCAL_WORD_ADDR_LSB];
  assign word_ack = (state_q == WORD_ACK);

  // Full-address reset vector words bypass the bounded backing-store alias.
  always_comb begin
    word_rdata = '0;
    if (latched_word_addr_q == RESET_VECTOR_ADDR) begin
      word_rdata = level0_vector[15:0];
    end else if (latched_word_addr_q == LEVEL0_VECTOR_HIGH_ADDR) begin
      word_rdata = level0_vector[31:16];
    end else if (int'(word_index) < DEPTH_WORDS) begin
      word_rdata = mem[word_index];
    end
  end

  // Sim-only initialization. The model is intentionally nonsynthesizable, so
  // an initial block and hierarchical testbench writes are permitted.
  initial begin
    level0_vector = LEVEL0_VECTOR_INIT;
    for (int unsigned i = 0; i < DEPTH_WORDS; i++) begin
      mem[i] = '0;
    end
  end

  // One-cycle physical-word target. Plain `always` permits the sim-only
  // initial block and testbenches to share the public memory array.
  always @(posedge clk) begin
    if (rst) begin
      state_q               <= WORD_IDLE;
      latched_word_addr_q   <= '0;
      latched_word_we_q     <= 1'b0;
      latched_word_wdata_q  <= '0;
    end else begin
      unique case (state_q)
        WORD_IDLE: begin
          if (word_req) begin
            latched_word_addr_q  <= word_addr;
            latched_word_we_q    <= word_we;
            latched_word_wdata_q <= word_wdata;
            state_q              <= WORD_ACK;
          end
        end

        WORD_ACK: begin
          if (latched_word_we_q) begin
            if (latched_word_addr_q == RESET_VECTOR_ADDR) begin
              level0_vector[15:0] <= latched_word_wdata_q;
            end else if (latched_word_addr_q == LEVEL0_VECTOR_HIGH_ADDR) begin
              level0_vector[31:16] <= latched_word_wdata_q;
            end else if (int'(word_index) < DEPTH_WORDS) begin
              mem[word_index] <= latched_word_wdata_q;
            end
          end
          state_q <= WORD_IDLE;
        end

        default: state_q <= WORD_IDLE;
      endcase
    end
  end

endmodule : sim_memory_model
