cd /home/andy/verilog_workspace/assume_board_is_nexys3 && source /opt/Xilinx/14.7/ISE_DS/settings64.sh && xtclsh <<'EOF'
project open assume_board_is_nexys3.xise
process run "Synthesize - XST"
process run "Implement Design"
process run "Generate Programming File"
project close
exit
EOF

cd /home/andy/verilog_workspace/assume_board_is_nexys3 && cat > burn.cmd <<'EOF'
setMode -bs
setCable -p auto
Identify
assignFile -p 1 -file clk_probe.bit
Program -p 1
quit
EOF

source /opt/Xilinx/14.7/ISE_DS/settings64.sh
impact -batch burn.cmd