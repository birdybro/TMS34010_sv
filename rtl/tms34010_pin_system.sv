// -----------------------------------------------------------------------------
// tms34010_pin_system.sv
//
// Integrated functional core/memory system plus the original-pin local-bus
// phase engine. tms34010_system remains entirely in core_clk_i; a coherent
// command/response MCP bridge is the only connection to bus_clk8x_i.
//
// The synchronous host-register request boundary and abstract HOLD request/
// acknowledge boundary remain exposed for later pin-wrapper tasks. Processor
// on-chip I/O requests already use LOCAL_CYCLE_IO_* and carry their internal
// read data through the coherent command bundle; host-indirect I/O routing is
// a following shared-register-port task.
// -----------------------------------------------------------------------------

`default_nettype none

module tms34010_pin_system
  import tms34010_pkg::*;
(
  input  logic                              core_clk_i,
  input  logic                              bus_clk8x_i,
  input  logic                              rst,

  input  logic                              run_emu_n_i,
  output logic                              emua_n_o,

  input  logic                              hcs_n_i,
  input  logic                              host_req_i,
  input  logic                              host_we_i,
  input  host_reg_sel_t                     host_reg_i,
  input  logic [1:0]                        host_be_i,
  input  local_word_t                       host_wdata_i,
  output local_word_t                       host_rdata_o,
  output logic                              host_ack_o,
  output logic                              host_busy_o,
  output logic                              hint_n_o,

  input  logic                              lint1_n_i,
  input  logic                              lint2_n_i,
  input  logic                              dpyint_set_i,

  input  logic                              hold_req_i,
  output logic                              hold_ack_o,

  output logic                              video_hsync_o,
  output logic                              video_vsync_o,
  output logic                              video_hblank_o,
  output logic                              video_vblank_o,
  output logic                              video_blank_o,

  input  logic                              lrdy_i,
  input  local_word_t                       lad_i,
  output local_word_t                       lad_o,
  output logic                              lad_oe_o,
  output logic                              lclk1_o,
  output logic                              lclk2_o,
  output logic                              ras_n_o,
  output logic                              lal_n_o,
  output logic                              cas_n_o,
  output logic                              we_n_o,
  output logic                              tr_qe_n_o,
  output logic                              den_n_o,
  output logic                              ddout_o,
  output local_subphase_t                   subphase_o,
  output logic                              local_init_done_o,
  output logic                              local_cycle_busy_o,
  output logic                              bridge_busy_o,

  output core_state_t                       state_o,
  output logic [ADDR_WIDTH-1:0]             pc_o,
  output instr_word_t                       instr_word_o,
  output logic                              illegal_opcode_o
);

  logic                              core_cycle_req;
  local_cycle_kind_t                 core_cycle_kind;
  logic [ADDR_WIDTH-1:0]             core_cycle_addr;
  local_word_t                       core_cycle_wdata;
  local_word_t                       core_cycle_io_rdata;
  logic                              core_cycle_iaq;
  logic [13:0]                       core_cycle_srfaddr;
  logic [15:0]                       core_cycle_dpytap;
  logic                              core_cycle_screen_org;
  logic [7:0]                        core_cycle_dram_row;
  local_word_t                       core_cycle_rdata;
  logic                              core_cycle_ack;

  local_cycle_cmd_t                  core_command;
  local_cycle_cmd_t                  local_command;
  logic                              local_cycle_req;
  local_word_t                       local_cycle_rdata;
  logic                              local_cycle_ack;

  always_comb begin
    core_command            = '0;
    core_command.kind       = core_cycle_kind;
    core_command.addr       = core_cycle_addr;
    core_command.wdata      = core_cycle_wdata;
    core_command.io_rdata   = core_cycle_io_rdata;
    core_command.iaq        = core_cycle_iaq;
    core_command.srfaddr    = core_cycle_srfaddr;
    core_command.dpytap     = core_cycle_dpytap;
    core_command.screen_org = core_cycle_screen_org;
    core_command.dram_row   = core_cycle_dram_row;
  end

  tms34010_system u_system (
    .clk                (core_clk_i),
    .rst                (rst),
    .run_emu_n_i        (run_emu_n_i),
    .emua_n_o           (emua_n_o),
    .hcs_n_i            (hcs_n_i),
    .host_req_i         (host_req_i),
    .host_we_i          (host_we_i),
    .host_reg_i         (host_reg_i),
    .host_be_i          (host_be_i),
    .host_wdata_i       (host_wdata_i),
    .host_rdata_o       (host_rdata_o),
    .host_ack_o         (host_ack_o),
    .host_busy_o        (host_busy_o),
    .hint_n_o           (hint_n_o),
    .lint1_n_i          (lint1_n_i),
    .lint2_n_i          (lint2_n_i),
    .dpyint_set_i       (dpyint_set_i),
    .hold_req_i         (hold_req_i),
    .hold_ack_o         (hold_ack_o),
    .video_hsync_o      (video_hsync_o),
    .video_vsync_o      (video_vsync_o),
    .video_hblank_o     (video_hblank_o),
    .video_vblank_o     (video_vblank_o),
    .video_blank_o      (video_blank_o),
    .cycle_req_o        (core_cycle_req),
    .cycle_kind_o       (core_cycle_kind),
    .cycle_addr_o       (core_cycle_addr),
    .cycle_wdata_o      (core_cycle_wdata),
    .cycle_io_rdata_o   (core_cycle_io_rdata),
    .cycle_iaq_o        (core_cycle_iaq),
    .cycle_srfaddr_o    (core_cycle_srfaddr),
    .cycle_dpytap_o     (core_cycle_dpytap),
    .cycle_screen_org_o (core_cycle_screen_org),
    .cycle_dram_row_o   (core_cycle_dram_row),
    .cycle_rdata_i      (core_cycle_rdata),
    .cycle_ack_i        (core_cycle_ack),
    .state_o            (state_o),
    .pc_o               (pc_o),
    .instr_word_o       (instr_word_o),
    .illegal_opcode_o   (illegal_opcode_o)
  );

  tms34010_local_bus_bridge u_local_bus_bridge (
    .src_clk_i   (core_clk_i),
    .src_rst_i   (rst),
    .src_req_i   (core_cycle_req),
    .src_cmd_i   (core_command),
    .src_rdata_o (core_cycle_rdata),
    .src_ack_o   (core_cycle_ack),
    .src_busy_o  (bridge_busy_o),
    .dst_clk_i   (bus_clk8x_i),
    .dst_rst_i   (rst),
    .dst_req_o   (local_cycle_req),
    .dst_cmd_o   (local_command),
    .dst_rdata_i (local_cycle_rdata),
    .dst_ack_i   (local_cycle_ack)
  );

  tms34010_local_bus u_local_bus (
    .clk8x_i            (bus_clk8x_i),
    .rst                (rst),
    .cycle_req_i        (local_cycle_req),
    .cycle_kind_i       (local_command.kind),
    .cycle_addr_i       (local_command.addr),
    .cycle_wdata_i      (local_command.wdata),
    .cycle_iaq_i        (local_command.iaq),
    .cycle_srfaddr_i    (local_command.srfaddr),
    .cycle_dpytap_i     (local_command.dpytap),
    .cycle_screen_org_i (local_command.screen_org),
    .cycle_dram_row_i   (local_command.dram_row),
    .io_rdata_i         (local_command.io_rdata),
    .cycle_rdata_o      (local_cycle_rdata),
    .cycle_ack_o        (local_cycle_ack),
    .cycle_busy_o       (local_cycle_busy_o),
    .init_done_o        (local_init_done_o),
    .lrdy_i             (lrdy_i),
    .lad_i              (lad_i),
    .lad_o              (lad_o),
    .lad_oe_o           (lad_oe_o),
    .lclk1_o            (lclk1_o),
    .lclk2_o            (lclk2_o),
    .ras_n_o            (ras_n_o),
    .lal_n_o            (lal_n_o),
    .cas_n_o            (cas_n_o),
    .we_n_o             (we_n_o),
    .tr_qe_n_o          (tr_qe_n_o),
    .den_n_o            (den_n_o),
    .ddout_o            (ddout_o),
    .subphase_o         (subphase_o)
  );

endmodule : tms34010_pin_system

`default_nettype wire
