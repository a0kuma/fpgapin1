module clk_probe(
    input  wire clk_in,
    input  wire pin_p16,
    output wire pin_p15,
    output wire [1:0] led
);

localparam integer CLK_HZ = 100_000_000;
localparam integer BAUD = 9600;
localparam integer BAUD_DIV = CLK_HZ / BAUD;
localparam integer RESP_LEN = 15;

localparam [1:0] RX_IDLE = 2'd0;
localparam [1:0] RX_START = 2'd1;
localparam [1:0] RX_DATA = 2'd2;
localparam [1:0] RX_STOP = 2'd3;

localparam [1:0] TX_IDLE = 2'd0;
localparam [1:0] TX_START = 2'd1;
localparam [1:0] TX_DATA = 2'd2;
localparam [1:0] TX_STOP = 2'd3;

reg [31:0] cnt = 32'd0;

reg rx_sync0 = 1'b1;
reg rx_sync1 = 1'b1;
reg [1:0] rx_state = RX_IDLE;
reg [13:0] rx_cnt = 14'd0;
reg [2:0] rx_bit = 3'd0;
reg [7:0] rx_shift = 8'd0;
reg [7:0] rx_byte = 8'd0;
reg rx_valid = 1'b0;

reg [4:0] q_idx = 5'd0;
reg [3:0] a_tens = 4'd0;
reg [3:0] a_ones = 4'd0;
reg [3:0] b_tens = 4'd0;
reg [3:0] b_ones = 4'd0;
reg [3:0] sum_h = 4'd0;
reg [3:0] sum_t = 4'd0;
reg [3:0] sum_o = 4'd0;

wire [7:0] num1 = (a_tens * 8'd10) + a_ones;
wire [7:0] num2 = (b_tens * 8'd10) + b_ones;

reg resp_pending = 1'b0;
reg [3:0] resp_idx = 4'd0;

reg [1:0] tx_state = TX_IDLE;
reg [13:0] tx_cnt = 14'd0;
reg [2:0] tx_bit = 3'd0;
reg [7:0] tx_shift = 8'd0;
reg tx_line = 1'b1;

function [7:0] resp_char;
    input [3:0] idx;
    begin
        case (idx)
            4'd0: resp_char = 8'h74; // t
            4'd1: resp_char = 8'h68; // h
            4'd2: resp_char = 8'h65; // e
            4'd3: resp_char = 8'h20; // space
            4'd4: resp_char = 8'h61; // a
            4'd5: resp_char = 8'h6e; // n
            4'd6: resp_char = 8'h73; // s
            4'd7: resp_char = 8'h20; // space
            4'd8: resp_char = 8'h69; // i
            4'd9: resp_char = 8'h73; // s
            4'd10: resp_char = 8'h20; // space
            4'd11: resp_char = 8'h30 + sum_h;
            4'd12: resp_char = 8'h30 + sum_t;
            4'd13: resp_char = 8'h30 + sum_o;
            4'd14: resp_char = 8'h2e; // .
            default: resp_char = 8'h20;
        endcase
    end
endfunction

always @(posedge clk_in) begin
    cnt <= cnt + 1'b1;

    rx_sync0 <= pin_p16;
    rx_sync1 <= rx_sync0;
    rx_valid <= 1'b0;

    case (rx_state)
        RX_IDLE: begin
            rx_cnt <= 14'd0;
            if (!rx_sync1) begin
                rx_state <= RX_START;
                rx_cnt <= BAUD_DIV[13:0] >> 1;
            end
        end
        RX_START: begin
            if (rx_cnt == 14'd0) begin
                if (!rx_sync1) begin
                    rx_state <= RX_DATA;
                    rx_cnt <= BAUD_DIV - 1;
                    rx_bit <= 3'd0;
                end else begin
                    rx_state <= RX_IDLE;
                end
            end else begin
                rx_cnt <= rx_cnt - 1'b1;
            end
        end
        RX_DATA: begin
            if (rx_cnt == 14'd0) begin
                rx_shift[rx_bit] <= rx_sync1;
                if (rx_bit == 3'd7) begin
                    rx_state <= RX_STOP;
                end else begin
                    rx_bit <= rx_bit + 1'b1;
                end
                rx_cnt <= BAUD_DIV - 1;
            end else begin
                rx_cnt <= rx_cnt - 1'b1;
            end
        end
        RX_STOP: begin
            if (rx_cnt == 14'd0) begin
                rx_state <= RX_IDLE;
                if (rx_sync1) begin
                    rx_byte <= rx_shift;
                    rx_valid <= 1'b1;
                end
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
    if (rx_valid) begin
        case (q_idx)
            5'd0: q_idx <= (rx_byte == 8'h77) ? 5'd1 : 5'd0; // w
            5'd1: q_idx <= (rx_byte == 8'h61) ? 5'd2 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // a
            5'd2: q_idx <= (rx_byte == 8'h68) ? 5'd3 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // h
            5'd3: q_idx <= (rx_byte == 8'h74) ? 5'd4 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // t
            5'd4: q_idx <= (rx_byte == 8'h20) ? 5'd5 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // space
            5'd5: q_idx <= (rx_byte == 8'h69) ? 5'd6 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // i
            5'd6: q_idx <= (rx_byte == 8'h73) ? 5'd7 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // s
            5'd7: q_idx <= (rx_byte == 8'h20) ? 5'd8 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // space
            5'd8: begin
                if (rx_byte >= 8'h30 && rx_byte <= 8'h39) begin
                    a_tens <= rx_byte - 8'h30;
                    q_idx <= 5'd9;
                end else begin
                    q_idx <= (rx_byte == 8'h77) ? 5'd1 : 5'd0;
                end
            end
            5'd9: begin
                if (rx_byte >= 8'h30 && rx_byte <= 8'h39) begin
                    a_ones <= rx_byte - 8'h30;
                    q_idx <= 5'd10;
                end else begin
                    q_idx <= (rx_byte == 8'h77) ? 5'd1 : 5'd0;
                end
            end
            5'd10: q_idx <= (rx_byte == 8'h20) ? 5'd11 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // space
            5'd11: q_idx <= (rx_byte == 8'h2b) ? 5'd12 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // +
            5'd12: q_idx <= (rx_byte == 8'h20) ? 5'd13 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // space
            5'd13: begin
                if (rx_byte >= 8'h30 && rx_byte <= 8'h39) begin
                    b_tens <= rx_byte - 8'h30;
                    q_idx <= 5'd14;
                end else begin
                    q_idx <= (rx_byte == 8'h77) ? 5'd1 : 5'd0;
                end
            end
            5'd14: begin
                if (rx_byte >= 8'h30 && rx_byte <= 8'h39) begin
                    b_ones <= rx_byte - 8'h30;
                    q_idx <= 5'd15;
                end else begin
                    q_idx <= (rx_byte == 8'h77) ? 5'd1 : 5'd0;
                end
            end
            5'd15: q_idx <= (rx_byte == 8'h20) ? 5'd16 : ((rx_byte == 8'h77) ? 5'd1 : 5'd0); // space
            5'd16: begin
                if (rx_byte == 8'h3f) begin
                    sum_h <= (num1 + num2) / 8'd100;
                    sum_t <= ((num1 + num2) % 8'd100) / 8'd10;
                    sum_o <= (num1 + num2) % 8'd10;
                    resp_pending <= 1'b1;
                    resp_idx <= 4'd0;
                    q_idx <= 5'd0;
                end else begin
                    q_idx <= (rx_byte == 8'h77) ? 5'd1 : 5'd0;
                end
            end
            default: q_idx <= 5'd0;
        endcase
    end

    if (tx_state == TX_IDLE) begin
        tx_line <= 1'b1;
        tx_cnt <= 14'd0;
        if (resp_pending) begin
            tx_shift <= resp_char(resp_idx);
            tx_state <= TX_START;
            tx_line <= 1'b0;
            tx_cnt <= 14'd0;
            tx_bit <= 3'd0;
            if (resp_idx == RESP_LEN - 1) begin
                resp_pending <= 1'b0;
                resp_idx <= 4'd0;
            end else begin
                resp_idx <= resp_idx + 1'b1;
            end
        end
    end else begin
        if (tx_cnt == BAUD_DIV - 1) begin
            tx_cnt <= 14'd0;
            case (tx_state)
                TX_START: begin
                    tx_state <= TX_DATA;
                    tx_line <= tx_shift[0];
                    tx_bit <= 3'd0;
                end
                TX_DATA: begin
                    if (tx_bit == 3'd7) begin
                        tx_state <= TX_STOP;
                        tx_line <= 1'b1;
                    end else begin
                        tx_bit <= tx_bit + 1'b1;
                        tx_line <= tx_shift[tx_bit + 1'b1];
                    end
                end
                TX_STOP: begin
                    tx_state <= TX_IDLE;
                    tx_line <= 1'b1;
                end
                default: begin
                    tx_state <= TX_IDLE;
                    tx_line <= 1'b1;
                end
            endcase
        end else begin
            tx_cnt <= tx_cnt + 1'b1;
        end
    end
end

assign pin_p15 = tx_line;
assign led[0] = cnt[27];
assign led[1] = 1'b0;

endmodule
