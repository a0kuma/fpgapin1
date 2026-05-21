module clk_probe (
    input  wire clk_in,
    input  wire uart_rx_can,
    input  wire uart_rx_cp2102,
    output wire slow_blink_clk_led,
    output wire unused_led,
    output wire unused_out,
    output wire uart_tx_can,
    output wire uart_tx_cp2102_inv
);

localparam integer CLK_HZ = 100_000_000;
localparam integer BAUD = 9600;
localparam integer BAUD_DIV = CLK_HZ / BAUD;
localparam integer BAUD_DIV_HALF = BAUD_DIV / 2;
localparam integer MSG_LEN = 12;

reg [31:0] cnt = 32'd0;
reg [13:0] baud_cnt = 14'd0;
wire baud_tick = (baud_cnt == BAUD_DIV - 1);

reg [1:0] state = 2'd0;
reg [2:0] bit_idx = 3'd0;
reg [3:0] msg_idx = 4'd0;
reg [7:0] tx_shift = 8'hFF;
reg tx_line = 1'b1;

localparam [1:0] RX_IDLE = 2'd0;
localparam [1:0] RX_START = 2'd1;
localparam [1:0] RX_DATA = 2'd2;
localparam [1:0] RX_STOP = 2'd3;

reg [1:0] rx_state = RX_IDLE;
reg [13:0] rx_cnt = 14'd0;
reg [2:0] rx_bit_idx = 3'd0;
reg [7:0] rx_shift = 8'd0;
reg [7:0] last_rx = 8'h20;

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
            4'd10: msg_byte = 8'h20; // space
            4'd11: msg_byte = last_rx;
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
    case (rx_state)
        RX_IDLE: begin
            if (uart_rx_cp2102 == 1'b0) begin
                rx_state <= RX_START;
                rx_cnt <= BAUD_DIV_HALF;
            end
        end
        RX_START: begin
            if (rx_cnt == 0) begin
                if (uart_rx_cp2102 == 1'b0) begin
                    rx_state <= RX_DATA;
                    rx_cnt <= BAUD_DIV - 1;
                    rx_bit_idx <= 3'd0;
                end else begin
                    rx_state <= RX_IDLE;
                end
            end else begin
                rx_cnt <= rx_cnt - 1'b1;
            end
        end
        RX_DATA: begin
            if (rx_cnt == 0) begin
                rx_shift[rx_bit_idx] <= uart_rx_cp2102;
                if (rx_bit_idx == 3'd7) begin
                    rx_state <= RX_STOP;
                end else begin
                    rx_bit_idx <= rx_bit_idx + 1'b1;
                end
                rx_cnt <= BAUD_DIV - 1;
            end else begin
                rx_cnt <= rx_cnt - 1'b1;
            end
        end
        RX_STOP: begin
            if (rx_cnt == 0) begin
                last_rx <= rx_shift;
                rx_state <= RX_IDLE;
            end else begin
                rx_cnt <= rx_cnt - 1'b1;
            end
        end
        default: begin
            rx_state <= RX_IDLE;
        end
    endcase
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

assign uart_tx_cp2102_inv = ~tx_line;
assign uart_tx_can = 1'b0;
assign unused_out = 1'b0;
assign slow_blink_clk_led = cnt[27];
assign unused_led = 1'b0;

endmodule
