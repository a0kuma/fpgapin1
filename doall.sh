#!/usr/bin/env bash
set -eo pipefail

WORKDIR="/home/andy/verilog_workspace/assume_board_is_nexys3"
XILINX_SETTINGS="/opt/Xilinx/14.7/ISE_DS/settings64.sh"
PROJECT="assume_board_is_nexys3.xise"
BITFILE="clk_probe.bit"

cd "$WORKDIR"

source "$XILINX_SETTINGS"

xtclsh <<'EOF'
project open assume_board_is_nexys3.xise
process run "Synthesize - XST"
process run "Implement Design"
process run "Generate Programming File"
project close
exit
EOF

cat > burn.cmd <<EOF
setMode -bs
setCable -p auto
Identify
assignFile -p 1 -file ${BITFILE}
Program -p 1
quit
EOF

impact -batch burn.cmd