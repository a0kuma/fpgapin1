module clk_probe #(
    parameter integer PIN_COUNT = 2
)(
    input  wire clk_in,
    output wire [PIN_COUNT-1:0] pin_out,
    output wire [1:0] led
);

localparam integer CLK_HZ = 100_000_000;
localparam integer BAUD = 9600;
localparam integer BAUD_DIV = CLK_HZ / BAUD;
localparam integer MSG_LEN = 10;

reg [31:0] cnt = 32'd0;
reg [13:0] baud_cnt = 14'd0;
wire baud_tick = (baud_cnt == BAUD_DIV - 1);

reg [1:0] state = 2'd0;
reg [2:0] bit_idx = 3'd0;
reg [3:0] msg_idx = 4'd0;
reg [7:0] tx_shift = 8'hFF;
reg tx_line = 1'b1;

function [7:0] msg_byte;
    input [3:0] idx;
    begin
        case (idx)
            4'd0: msg_byte = 8'h68; // h
            4'd1: msg_byte = 8'h65; // e
            4'd2: msg_byte = 8'h6c; // l
            4'd3: msg_byte = 8'h6c; // l
            4'd4: msg_byte = 8'h6f; // o
            4'd5: msg_byte = 8'h20; // space
            4'd6: msg_byte = 8'h77; // w
            4'd7: msg_byte = 8'h6f; // o
            4'd8: msg_byte = 8'h72; // r
            4'd9: msg_byte = 8'h64; // d
            default: msg_byte = 8'h20;
        endcase
    end
endfunction

always @(posedge clk_in) begin
    cnt <= cnt + 1'b1;
    if (baud_cnt == BAUD_DIV - 1) begin
        baud_cnt <= 14'd0;
    end else begin
        baud_cnt <= baud_cnt + 1'b1;
    end
end

always @(posedge clk_in) begin
    if (baud_tick) begin
        case (state)
            2'd0: begin
                tx_line <= 1'b1;
                tx_shift <= msg_byte(msg_idx);
                state <= 2'd1;
            end
            2'd1: begin
                tx_line <= 1'b0;
                bit_idx <= 3'd0;
                state <= 2'd2;
            end
            2'd2: begin
                tx_line <= tx_shift[bit_idx];
                if (bit_idx == 3'd7) begin
                    state <= 2'd3;
                end else begin
                    bit_idx <= bit_idx + 1'b1;
                end
            end
            2'd3: begin
                tx_line <= 1'b1;
                if (msg_idx == MSG_LEN - 1) begin
                    msg_idx <= 4'd0;
                end else begin
                    msg_idx <= msg_idx + 1'b1;
                end
                state <= 2'd0;
            end
            default: begin
                state <= 2'd0;
                tx_line <= 1'b1;
            end
        endcase
    end
end

assign pin_out = {1'b0, tx_line};
assign led[0] = cnt[27];
assign led[1] = 1'b0;

endmodule
