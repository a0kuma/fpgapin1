module clk_probe(
    input  wire clk_in,
    output wire [1:0] led
);

reg [31:0] cnt = 32'd0;

always @(posedge clk_in) begin
    cnt <= cnt + 1'b1;
end

// 兩種不同除頻速度：
// 如果 clk 約 100 MHz，led[0] 快閃、led[1] 慢閃
// 如果 clk 約 12 MHz，led[0] 仍然看得到閃爍
assign led[1] = cnt[22];
assign led[0] = cnt[26];

endmodule