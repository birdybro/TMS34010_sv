#!/bin/bash
# B1: timing/size-only Quartus project, tms34010_system as top, every port a virtual pin
# (host interface included), clk at 50 MHz. Usage: mk_b1.sh <dir> <CYCLE_ACCURATE 0|1> <CLKS_PER_STATE> [period_ns]
set -e
D=$1; CA=$2; CPS=$3; PER=${4:-20.000}
R=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p $R/work/$D && cd $R/work/$D
{ echo 'set_global_assignment -name FAMILY "Cyclone V"'
  echo 'set_global_assignment -name DEVICE 5CSEBA6U23I7'
  echo 'set_global_assignment -name TOP_LEVEL_ENTITY b1_top'
  echo 'set_global_assignment -name SDC_FILE b1.sdc'
  echo 'set_global_assignment -name NUM_PARALLEL_PROCESSORS 4'
  echo 'set_global_assignment -name SEED 1'
  echo 'set_global_assignment -name OPTIMIZATION_MODE "HIGH PERFORMANCE EFFORT"'
  echo 'set_global_assignment -name MIN_CORE_JUNCTION_TEMP -40'
  echo "set_global_assignment -name SYSTEMVERILOG_FILE $R/rtl/tms34010_pkg.sv"
  for f in $(find $R/rtl -name '*.sv' ! -name tms34010_pkg.sv ! -path '*/fpga/*' ! -name tms34010_pin_system.sv | sort); do
    echo "set_global_assignment -name SYSTEMVERILOG_FILE $f"; done
  echo "set_global_assignment -name SYSTEMVERILOG_FILE $R/work/$D/b1_top.sv"
  for p in rst vrst hs_n vs_n run_emu_n hcs_n host_req host_we "host_reg[*]" host_reg "host_be[*]" "host_wdata[*]" \
           "host_rdata[*]" host_ack host_busy hint_n emua_n lint1_n lint2_n dpyint_set hold_req "cycle_rdata[*]" \
           cycle_ack hold_ack cycle_req cycle_iaq cycle_org ill "cycle_kind[*]" "cycle_addr[*]" "pc[*]" \
           "cycle_wdata[*]" "cycle_io_rdata[*]" "cycle_srfaddr[*]" "cycle_dpytap[*]" "cycle_row[*]" \
           hs vs hb vb bl hs_oe vs_oe; do
    echo "set_instance_assignment -name VIRTUAL_PIN ON -to $p"; done
} > b1.qsf
echo 'PROJECT_REVISION = "b1"' > b1.qpf
cat > b1_top.sv <<SV
// B1 measuring wrapper: tms34010_system with every port a virtual pin.
module b1_top
  import tms34010_pkg::*;
(
  input  logic clk, vclk, rst, vrst, hs_n, vs_n, run_emu_n,
  input  logic hcs_n, host_req, host_we,
  input  host_reg_sel_t host_reg,
  input  logic [1:0] host_be,
  input  local_word_t host_wdata,
  output local_word_t host_rdata,
  output logic host_ack, host_busy, hint_n, emua_n,
  input  logic lint1_n, lint2_n, dpyint_set, hold_req,
  input  local_word_t cycle_rdata,
  input  logic cycle_ack,
  output logic hold_ack, cycle_req, cycle_iaq, cycle_org, ill,
  output local_cycle_kind_t cycle_kind,
  output logic [31:0] cycle_addr, pc,
  output local_word_t cycle_wdata, cycle_io_rdata,
  output logic [13:0] cycle_srfaddr,
  output logic [15:0] cycle_dpytap,
  output logic [7:0] cycle_row,
  output logic hs, vs, hb, vb, bl, hs_oe, vs_oe
);
  tms34010_system #(.CLKS_PER_STATE($CPS), .CYCLE_ACCURATE(1'b$CA)) u_tms (
    .clk(clk), .vclk_i(vclk), .rst(rst), .vclk_rst_i(vrst),
    .video_hsync_n_i(hs_n), .video_vsync_n_i(vs_n), .run_emu_n_i(run_emu_n), .emua_n_o(emua_n),
    .hcs_n_i(hcs_n), .host_req_i(host_req), .host_we_i(host_we), .host_reg_i(host_reg), .host_be_i(host_be),
    .host_wdata_i(host_wdata), .host_rdata_o(host_rdata), .host_ack_o(host_ack), .host_busy_o(host_busy), .hint_n_o(hint_n),
    .lint1_n_i(lint1_n), .lint2_n_i(lint2_n), .dpyint_set_i(dpyint_set),
    .hold_req_i(hold_req), .hold_ack_o(hold_ack),
    .video_hsync_o(hs), .video_vsync_o(vs), .video_hblank_o(hb), .video_vblank_o(vb),
    .video_blank_o(bl), .video_hsync_oe_o(hs_oe), .video_vsync_oe_o(vs_oe),
    .cycle_req_o(cycle_req), .cycle_kind_o(cycle_kind), .cycle_addr_o(cycle_addr),
    .cycle_wdata_o(cycle_wdata), .cycle_io_rdata_o(cycle_io_rdata), .cycle_iaq_o(cycle_iaq),
    .cycle_srfaddr_o(cycle_srfaddr), .cycle_dpytap_o(cycle_dpytap), .cycle_screen_org_o(cycle_org),
    .cycle_dram_row_o(cycle_row), .cycle_rdata_i(cycle_rdata), .cycle_ack_i(cycle_ack),
    .state_o(), .pc_o(pc), .instr_word_o(), .illegal_opcode_o(ill)
  );
endmodule
SV
# clocks + the CPU's own exceptions (fpga/tms34010_core.sdc, read as a game core would)
{ echo "create_clock -name clk  -period $PER [get_ports clk]"
  echo "create_clock -name vclk -period 20.000 [get_ports vclk]"
  echo "set_clock_groups -asynchronous -group clk -group vclk"
  echo "derive_clock_uncertainty"
  echo "source $R/fpga/tms34010_core.sdc"
} > b1.sdc
cat > report.tcl <<'T'
project_open b1
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_clock_fmax_summary -file fmax.rpt
report_timing -setup -npaths 1000 -detail summary -file worst_setup.rpt
report_timing -setup -npaths 10 -detail path_only -file worst_paths.rpt
project_close
T
cat > build.sh <<B
#!/bin/bash
cd $R/work/$D
export PATH="/mnt/c/intelfpga_lite/17.0/quartus/bin64:\$PATH"
rm -f DONE
quartus_sh.exe --flow compile b1 > build.log 2>&1
quartus_sta.exe -t report.tcl > sta.log 2>&1
if grep -q "Full Compilation was successful" build.log; then echo OK > DONE; else echo FAIL > DONE; fi
B
chmod +x build.sh
