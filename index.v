module clk_probe #(
    parameter integer PIN_COUNT = 225
)(
    input  wire clk_in,
    input  wire [PIN_COUNT-1:0] pin_in,
    output wire [1:0] led
);

reg [31:0] cnt = 32'd0;

reg [7:0] por_cnt = 8'd0;
reg por_done = 1'b0;

reg [PIN_COUNT-1:0] pin_sync0;
reg [PIN_COUNT-1:0] pin_sync1;
reg [PIN_COUNT-1:0] pin_prev;
wire any_edge = |(pin_sync1 ^ pin_prev);

reg match_latched = 1'b0;

always @(posedge clk_in) begin
    cnt <= cnt + 1'b1;
end

always @(posedge clk_in) begin
    pin_sync0 <= pin_in;
    pin_sync1 <= pin_sync0;

    if (!por_done) begin
        por_cnt <= por_cnt + 1'b1;
        if (por_cnt == 8'hFF) begin
            por_done <= 1'b1;
        end
        match_latched <= 1'b0;
        pin_prev <= pin_sync1;
    end else begin
        pin_prev <= pin_sync1;
        if (any_edge) begin
            match_latched <= 1'b1;
        end
    end
end

assign led[0] = cnt[27];
assign led[1] = match_latched;

endmodule