// -----------------------------------------------------------------------------
// tms34010_memory_fabric.sv
//
// Integrated abstract memory fabric for the TMS34010 clients.
//
// The CPU/graphics side retains the core's architectural 1..32-bit,
// bit-addressed request boundary. The field sequencer expands that request
// into aligned 16-bit words, and the fixed-priority arbiter combines those
// words with screen refresh, DRAM refresh, host indirect access, and HOLD.
// Processor on-chip I/O transactions bypass field splitting and select the
// dedicated I/O read/write cycle kinds with their internal read-data payload.
// One abstract controller-facing cycle remains held until acknowledgement.
//
// This module deliberately stops before original-pin phase generation. A
// following local-bus controller converts local_cycle_kind_t plus the selected
// payload into LAD/RAS/CAS/LAL/DEN/DDOUT/W/LRDY behavior.
//
// Spec sources:
//   - 1988 TMS34010 User's Guide §4.1, pages 4-2 through 4-5
//     (architectural fields to aligned 16-bit words).
//   - 1988 TMS34010 User's Guide §11.3, page 11-4
//     (client priority, cycle completion, RMW atomicity, and HOLD restart).
// -----------------------------------------------------------------------------

`default_nettype none

module tms34010_memory_fabric
  import tms34010_pkg::*;
(
  input  logic                              clk,
  input  logic                              rst,

  input  logic                              cpu_field_req_i,
  input  logic                              cpu_field_we_i,
  input  logic [ADDR_WIDTH-1:0]             cpu_field_addr_i,
  input  logic [FIELD_SIZE_WIDTH-1:0]       cpu_field_size_i,
  input  logic [DATA_WIDTH-1:0]             cpu_field_wdata_i,
  input  logic                              cpu_field_iaq_i,
  input  logic                              cpu_field_is_io_i,
  input  logic                              cpu_field_io_we_i,
  input  local_word_t                       cpu_field_io_rdata_i,
  output logic [DATA_WIDTH-1:0]             cpu_field_rdata_o,
  output logic                              cpu_field_ack_o,

  input  logic                              host_req_i,
  input  logic                              host_we_i,
  input  logic [ADDR_WIDTH-1:0]             host_addr_i,
  input  local_word_t                       host_wdata_i,
  output local_word_t                       host_rdata_o,
  output logic                              host_ack_o,

  input  logic                              screen_req_i,
  input  logic [13:0]                       screen_srfaddr_i,
  input  logic [15:0]                       screen_dpytap_i,
  input  logic                              screen_org_i,
  output logic                              screen_ack_o,

  input  logic                              dram_req_i,
  input  logic [7:0]                        dram_row_i,
  input  logic                              dram_cbr_i,

  input  logic                              hold_req_i,
  output logic                              hold_ack_o,

  output logic                              cycle_req_o,
  output local_cycle_kind_t                 cycle_kind_o,
  output logic [ADDR_WIDTH-1:0]             cycle_addr_o,
  output local_word_t                       cycle_wdata_o,
  output local_word_t                       cycle_io_rdata_o,
  output logic                              cycle_iaq_o,
  output logic [13:0]                       cycle_srfaddr_o,
  output logic [15:0]                       cycle_dpytap_o,
  output logic                              cycle_screen_org_o,
  output logic [7:0]                        cycle_dram_row_o,
  input  local_word_t                       cycle_rdata_i,
  input  logic                              cycle_ack_i
);

  logic                          cpu_word_req;
  logic                          cpu_word_we;
  logic [ADDR_WIDTH-1:0]         cpu_word_addr;
  local_word_t                   cpu_word_wdata;
  local_word_t                   cpu_word_rdata;
  logic                          cpu_word_ack;
  logic                          cpu_word_rmw_lock;
  logic                          cpu_word_restart;
  logic [DATA_WIDTH-1:0]         sequenced_field_rdata;
  logic                          sequenced_field_ack;
  logic                          selected_cpu_req;
  logic                          selected_cpu_we;
  logic [ADDR_WIDTH-1:0]         selected_cpu_addr;
  local_word_t                   selected_cpu_wdata;
  logic                          selected_cpu_rmw_lock;
  logic                          cpu_request_active_q;
  logic                          cpu_request_is_io_q;
  logic                          cpu_request_io_we_q;
  logic [ADDR_WIDTH-1:0]         cpu_request_addr_q;
  logic [FIELD_SIZE_WIDTH-1:0]   cpu_request_size_q;
  logic [DATA_WIDTH-1:0]         cpu_request_wdata_q;
  logic                          cpu_request_iaq_q;
  local_word_t                   cpu_request_io_rdata_q;

  // Register the architectural request before classifying it as external
  // field traffic or an on-chip I/O cycle. Besides holding the complete
  // transaction, this stage breaks any combinational acknowledge-to-address-
  // decode path through the core's monolithic control block.
  always_ff @(posedge clk) begin
    if (rst) begin
      cpu_request_active_q   <= 1'b0;
      cpu_request_is_io_q    <= 1'b0;
      cpu_request_io_we_q    <= 1'b0;
      cpu_request_addr_q     <= '0;
      cpu_request_size_q     <= '0;
      cpu_request_wdata_q    <= '0;
      cpu_request_iaq_q      <= 1'b0;
      cpu_request_io_rdata_q <= '0;
    end else if (cpu_request_active_q) begin
      if (cpu_field_ack_o)
        cpu_request_active_q <= 1'b0;
    end else if (cpu_field_req_i) begin
      cpu_request_active_q   <= 1'b1;
      cpu_request_is_io_q    <= cpu_field_is_io_i;
      cpu_request_io_we_q    <= cpu_field_is_io_i
                              ? cpu_field_io_we_i
                              : cpu_field_we_i;
      cpu_request_addr_q     <= cpu_field_addr_i;
      cpu_request_size_q     <= cpu_field_size_i;
      cpu_request_wdata_q    <= cpu_field_wdata_i;
      cpu_request_iaq_q      <= cpu_field_iaq_i;
      cpu_request_io_rdata_q <= cpu_field_io_rdata_i;
    end
  end

  tms34010_field_sequencer u_field_sequencer (
    .clk             (clk),
    .rst             (rst),
    .field_req_i     (cpu_request_active_q && !cpu_request_is_io_q),
    .field_we_i      (cpu_request_io_we_q),
    .field_addr_i    (cpu_request_addr_q),
    .field_size_i    (cpu_request_size_q),
    .field_wdata_i   (cpu_request_wdata_q),
    .field_rdata_o   (sequenced_field_rdata),
    .field_ack_o     (sequenced_field_ack),
    .word_req_o      (cpu_word_req),
    .word_we_o       (cpu_word_we),
    .word_addr_o     (cpu_word_addr),
    .word_wdata_o    (cpu_word_wdata),
    .word_rdata_i    (cpu_word_rdata),
    .word_ack_i      (cpu_word_ack),
    .word_restart_i  (cpu_word_restart),
    .word_rmw_lock_o (cpu_word_rmw_lock)
  );

  always_comb begin
    selected_cpu_req      = cpu_word_req;
    selected_cpu_we       = cpu_word_we;
    selected_cpu_addr     = cpu_word_addr;
    selected_cpu_wdata    = cpu_word_wdata;
    selected_cpu_rmw_lock = cpu_word_rmw_lock;

    if (cpu_request_is_io_q) begin
      selected_cpu_req      = cpu_request_active_q;
      selected_cpu_we       = cpu_request_io_we_q;
      selected_cpu_addr     = cpu_request_addr_q;
      selected_cpu_wdata    = cpu_request_wdata_q[LOCAL_WORD_WIDTH-1:0];
      selected_cpu_rmw_lock = 1'b0;
    end
  end

  assign cpu_field_rdata_o = cpu_request_is_io_q
      ? {{(DATA_WIDTH-LOCAL_WORD_WIDTH){1'b0}}, cpu_request_io_rdata_q}
      : sequenced_field_rdata;
  assign cpu_field_ack_o = cpu_request_active_q
      && (cpu_request_is_io_q ? cpu_word_ack : sequenced_field_ack);

  tms34010_bus_arbiter u_arbiter (
    .clk               (clk),
    .rst               (rst),
    .hold_req_i        (hold_req_i),
    .hold_ack_o        (hold_ack_o),
    .screen_req_i      (screen_req_i),
    .screen_srfaddr_i  (screen_srfaddr_i),
    .screen_dpytap_i   (screen_dpytap_i),
    .screen_org_i      (screen_org_i),
    .screen_ack_o      (screen_ack_o),
    .dram_req_i        (dram_req_i),
    .dram_row_i        (dram_row_i),
    .dram_cbr_i        (dram_cbr_i),
    .dram_ack_o        (),
    .host_req_i        (host_req_i),
    .host_we_i         (host_we_i),
    .host_addr_i       (host_addr_i),
    .host_wdata_i      (host_wdata_i),
    .host_rdata_o      (host_rdata_o),
    .host_ack_o        (host_ack_o),
    .cpu_req_i         (selected_cpu_req),
    .cpu_we_i          (selected_cpu_we),
    .cpu_addr_i        (selected_cpu_addr),
    .cpu_wdata_i       (selected_cpu_wdata),
    .cpu_io_i          (cpu_request_is_io_q),
    .cpu_io_rdata_i    (cpu_request_io_rdata_q),
    .cpu_iaq_i         (cpu_request_iaq_q),
    .cpu_rmw_lock_i    (selected_cpu_rmw_lock),
    .cpu_rdata_o       (cpu_word_rdata),
    .cpu_ack_o         (cpu_word_ack),
    .cpu_restart_o     (cpu_word_restart),
    .cycle_req_o       (cycle_req_o),
    .cycle_kind_o      (cycle_kind_o),
    .cycle_addr_o      (cycle_addr_o),
    .cycle_wdata_o     (cycle_wdata_o),
    .cycle_io_rdata_o  (cycle_io_rdata_o),
    .cycle_iaq_o       (cycle_iaq_o),
    .cycle_srfaddr_o   (cycle_srfaddr_o),
    .cycle_dpytap_o    (cycle_dpytap_o),
    .cycle_screen_org_o(cycle_screen_org_o),
    .cycle_dram_row_o  (cycle_dram_row_o),
    .cycle_rdata_i     (cycle_rdata_i),
    .cycle_ack_i       (cycle_ack_i)
  );

endmodule : tms34010_memory_fabric

`default_nettype wire
