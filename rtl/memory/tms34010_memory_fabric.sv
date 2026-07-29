// -----------------------------------------------------------------------------
// tms34010_memory_fabric.sv
//
// Integrated abstract memory fabric for the TMS34010 clients.
//
// The CPU/graphics side retains the core's architectural 1..32-bit,
// bit-addressed request boundary. The field sequencer expands that request
// into aligned 16-bit words, and the fixed-priority arbiter combines those
// words with screen refresh, DRAM refresh, host indirect access, and HOLD.
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
  output logic [13:0]                       cycle_srfaddr_o,
  output logic [15:0]                       cycle_dpytap_o,
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

  tms34010_field_sequencer u_field_sequencer (
    .clk             (clk),
    .rst             (rst),
    .field_req_i     (cpu_field_req_i),
    .field_we_i      (cpu_field_we_i),
    .field_addr_i    (cpu_field_addr_i),
    .field_size_i    (cpu_field_size_i),
    .field_wdata_i   (cpu_field_wdata_i),
    .field_rdata_o   (cpu_field_rdata_o),
    .field_ack_o     (cpu_field_ack_o),
    .word_req_o      (cpu_word_req),
    .word_we_o       (cpu_word_we),
    .word_addr_o     (cpu_word_addr),
    .word_wdata_o    (cpu_word_wdata),
    .word_rdata_i    (cpu_word_rdata),
    .word_ack_i      (cpu_word_ack),
    .word_restart_i  (cpu_word_restart),
    .word_rmw_lock_o (cpu_word_rmw_lock)
  );

  tms34010_bus_arbiter u_arbiter (
    .clk               (clk),
    .rst               (rst),
    .hold_req_i        (hold_req_i),
    .hold_ack_o        (hold_ack_o),
    .screen_req_i      (screen_req_i),
    .screen_srfaddr_i  (screen_srfaddr_i),
    .screen_dpytap_i   (screen_dpytap_i),
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
    .cpu_req_i         (cpu_word_req),
    .cpu_we_i          (cpu_word_we),
    .cpu_addr_i        (cpu_word_addr),
    .cpu_wdata_i       (cpu_word_wdata),
    .cpu_rmw_lock_i    (cpu_word_rmw_lock),
    .cpu_rdata_o       (cpu_word_rdata),
    .cpu_ack_o         (cpu_word_ack),
    .cpu_restart_o     (cpu_word_restart),
    .cycle_req_o       (cycle_req_o),
    .cycle_kind_o      (cycle_kind_o),
    .cycle_addr_o      (cycle_addr_o),
    .cycle_wdata_o     (cycle_wdata_o),
    .cycle_srfaddr_o   (cycle_srfaddr_o),
    .cycle_dpytap_o    (cycle_dpytap_o),
    .cycle_dram_row_o  (cycle_dram_row_o),
    .cycle_rdata_i     (cycle_rdata_i),
    .cycle_ack_i       (cycle_ack_i)
  );

endmodule : tms34010_memory_fabric

`default_nettype wire
