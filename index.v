module clk_probe #(
    parameter integer PIN_COUNT = 225
)(
    input  wire clk_in,
    input  wire [PIN_COUNT-1:0] pin_in,
    output wire [1:0] led
);

localparam integer CLK_HZ = 100_000_000;
localparam integer HIGH_SECS = 10;
localparam integer CNT_WIDTH = 30;
localparam [CNT_WIDTH-1:0] COUNT_MAX = (CLK_HZ * HIGH_SECS) - 1;

reg [31:0] cnt = 32'd0;

reg [7:0] por_cnt = 8'd0;
reg por_done = 1'b0;

reg [PIN_COUNT-1:0] pin_sync0;
reg [PIN_COUNT-1:0] pin_sync1;
reg [CNT_WIDTH-1:0] high_cnt = {CNT_WIDTH{1'b0}};
wire any_high = |pin_sync1;

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
        high_cnt <= {CNT_WIDTH{1'b0}};
    end else begin
        if (any_high) begin
            if (high_cnt < COUNT_MAX) begin
                high_cnt <= high_cnt + 1'b1;
                if (high_cnt == COUNT_MAX - 1'b1) begin
                    match_latched <= 1'b1;
                end
            end else begin
                high_cnt <= high_cnt;
                match_latched <= 1'b1;
            end
        end else begin
            high_cnt <= {CNT_WIDTH{1'b0}};
        end
    end
end

assign led[0] = cnt[27];
assign led[1] = match_latched;

endmodule