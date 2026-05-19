module clk_probe(
    input  wire clk_in,
    input  wire pin_p16,
    output wire [1:0] led
);

reg [31:0] cnt = 32'd0;
reg pin_sync0 = 1'b0;
reg pin_sync1 = 1'b0;

always @(posedge clk_in) begin
    cnt <= cnt + 1'b1;
    pin_sync0 <= pin_p16;
    pin_sync1 <= pin_sync0;
end

assign led[0] = cnt[27];
assign led[1] = pin_sync1;

endmodule
