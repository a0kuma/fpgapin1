module clk_probe #(
    parameter integer PIN_COUNT = 225
)(
    input  wire clk_in,
    input  wire [PIN_COUNT-1:0] pin_in,
    output wire [1:0] led
);

localparam integer CLK_HZ = 100_000_000;
localparam integer BAUD = 9600;
localparam integer OVERSAMPLE = 16;
localparam integer BAUD_DIV = CLK_HZ / (BAUD * OVERSAMPLE);

reg [31:0] cnt = 32'd0;
reg [15:0] baud_cnt = 16'd0;
wire tick_16x = (baud_cnt == BAUD_DIV - 1);

reg [7:0] por_cnt = 8'd0;
reg por_done = 1'b0;

reg [PIN_COUNT-1:0] pin_sync0;
reg [PIN_COUNT-1:0] pin_sync1;

reg [1:0] state [0:PIN_COUNT-1];
reg [3:0] sample_cnt [0:PIN_COUNT-1];
reg [2:0] bit_idx [0:PIN_COUNT-1];
reg [7:0] shift [0:PIN_COUNT-1];

reg any_match = 1'b0;
reg match_latched = 1'b0;

integer i;

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
        baud_cnt <= 16'd0;
        any_match <= 1'b0;
        for (i = 0; i < PIN_COUNT; i = i + 1) begin
            state[i] <= 2'd0;
            sample_cnt[i] <= 4'd0;
            bit_idx[i] <= 3'd0;
            shift[i] <= 8'd0;
        end
    end else begin
        if (tick_16x) begin
            baud_cnt <= 16'd0;
            any_match <= 1'b0;
            for (i = 0; i < PIN_COUNT; i = i + 1) begin
                case (state[i])
                    2'd0: begin
                        if (!pin_sync1[i]) begin
                            state[i] <= 2'd1;
                            sample_cnt[i] <= 4'd0;
                        end
                    end
                    2'd1: begin
                        if (sample_cnt[i] == 4'd7) begin
                            if (!pin_sync1[i]) begin
                                state[i] <= 2'd2;
                                bit_idx[i] <= 3'd0;
                                sample_cnt[i] <= 4'd0;
                            end else begin
                                state[i] <= 2'd0;
                            end
                        end else begin
                            sample_cnt[i] <= sample_cnt[i] + 1'b1;
                        end
                    end
                    2'd2: begin
                        if (sample_cnt[i] == 4'd15) begin
                            shift[i][bit_idx[i]] <= pin_sync1[i];
                            sample_cnt[i] <= 4'd0;
                            if (bit_idx[i] == 3'd7) begin
                                state[i] <= 2'd3;
                            end else begin
                                bit_idx[i] <= bit_idx[i] + 1'b1;
                            end
                        end else begin
                            sample_cnt[i] <= sample_cnt[i] + 1'b1;
                        end
                    end
                    2'd3: begin
                        if (sample_cnt[i] == 4'd15) begin
                            if (pin_sync1[i] && shift[i] == 8'h3A) begin
                                any_match <= 1'b1;
                            end
                            state[i] <= 2'd0;
                            sample_cnt[i] <= 4'd0;
                        end else begin
                            sample_cnt[i] <= sample_cnt[i] + 1'b1;
                        end
                    end
                    default: begin
                        state[i] <= 2'd0;
                        sample_cnt[i] <= 4'd0;
                    end
                endcase
            end
        end else begin
            baud_cnt <= baud_cnt + 1'b1;
            any_match <= 1'b0;
        end
    end
end

always @(posedge clk_in) begin
    if (!por_done) begin
        match_latched <= 1'b0;
    end else if (any_match) begin
        match_latched <= 1'b1;
    end
end

assign led[0] = cnt[27];
assign led[1] = match_latched;

endmodule