module clk_probe (
    input  wire clk_in,
    output wire uart_rx_can,
    input  wire uart_rx_cp2102,
    output wire slow_blink_clk_led,
    output wire unused_led,
    output wire unused_out,
    input  wire uart_tx_can,
    output wire uart_tx_cp2102_inv
);

localparam integer CLK_HZ = 100_000_000;
localparam integer CAN_BITRATE = 500_000;
localparam integer UART_BAUD = 9600;

reg [31:0] cnt = 32'd0;
reg [20:0] rst_cnt = 21'd0;
reg reset = 1'b1;

always @(posedge clk_in) begin
    cnt <= cnt + 1'b1;
    if (reset) begin
        rst_cnt <= rst_cnt + 1'b1;
        if (rst_cnt == 21'h1FFFFF) begin
            reset <= 1'b0;
        end
    end
end

wire can_tx;
wire dbg_uart_tx;

raw_can_listener #(
    .CLK_HZ(CLK_HZ),
    .UART_BAUD(UART_BAUD)
) raw_listener (
    .clk(clk_in),
    .reset(reset),
    .can_rx(uart_tx_can),
    .can_tx(can_tx),
    .uart_tx(dbg_uart_tx)
);

// CORRECT pin mapping (verified via loopback): N15=CAN RX, P15=CAN TX
assign uart_rx_can = can_tx;
assign uart_tx_cp2102_inv = ~dbg_uart_tx;
assign slow_blink_clk_led = cnt[27];
assign unused_led = 1'b0;
assign unused_out = 1'b0;

endmodule


module raw_can_listener #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer UART_BAUD = 9600
) (
    input  wire clk,
    input  wire reset,
    input  wire can_rx,
    output wire can_tx,
    output wire uart_tx
);

assign can_tx = 1'b1; // Passive test: never drive CAN dominant, not even ACK.

reg can_rx_ff1 = 1'b1;
reg can_rx_ff2 = 1'b1;
reg can_rx_prev = 1'b1;
wire can_rx_s = can_rx_ff2;

reg edge_seen = 1'b0;
reg low_seen = 1'b0;
reg [3:0] edge_count = 4'd0;
reg [3:0] low_count = 4'd0;

localparam integer HB_INTERVAL = CLK_HZ;
reg [31:0] hb_cnt = 32'd0;
reg hb_pending = 1'b0;

reg uart_start = 1'b0;
reg [7:0] uart_byte = 8'd0;
wire uart_busy;
reg [3:0] out_state = 4'd0;

function [7:0] hex_char;
    input [3:0] value;
    begin
        hex_char = (value < 4'd10) ? (8'h30 + value) : (8'h41 + value - 4'd10);
    end
endfunction

uart_tx #(
    .CLK_HZ(CLK_HZ),
    .BAUD(UART_BAUD)
) dbg_uart (
    .clk(clk),
    .reset(reset),
    .tx_start(uart_start),
    .tx_data(uart_byte),
    .tx_busy(uart_busy),
    .tx_line(uart_tx)
);

always @(posedge clk) begin
    if (reset) begin
        can_rx_ff1 <= 1'b1;
        can_rx_ff2 <= 1'b1;
        can_rx_prev <= 1'b1;
        edge_seen <= 1'b0;
        low_seen <= 1'b0;
        edge_count <= 4'd0;
        low_count <= 4'd0;
        hb_cnt <= 32'd0;
        hb_pending <= 1'b0;
        uart_start <= 1'b0;
        uart_byte <= 8'd0;
        out_state <= 4'd0;
    end else begin
        uart_start <= 1'b0;

        can_rx_ff1 <= can_rx;
        can_rx_ff2 <= can_rx_ff1;
        can_rx_prev <= can_rx_s;

        if (can_rx_s != can_rx_prev) begin
            edge_seen <= 1'b1;
            if (edge_count != 4'hF) begin
                edge_count <= edge_count + 1'b1;
            end
        end

        if (!can_rx_s) begin
            low_seen <= 1'b1;
            if (low_count != 4'hF) begin
                low_count <= low_count + 1'b1;
            end
        end

        if (hb_cnt >= HB_INTERVAL - 1) begin
            hb_cnt <= 32'd0;
            hb_pending <= 1'b1;
        end else begin
            hb_cnt <= hb_cnt + 1'b1;
        end

        case (out_state)
            4'd0: begin
                if (hb_pending && !uart_busy && !uart_start) begin
                    uart_byte <= 8'h4C; // 'L'
                    uart_start <= 1'b1;
                    out_state <= 4'd1;
                end
            end
            4'd1: begin
                if (!uart_busy && !uart_start) begin
                    uart_byte <= can_rx_s ? 8'h31 : 8'h30;
                    uart_start <= 1'b1;
                    out_state <= 4'd2;
                end
            end
            4'd2: begin
                if (!uart_busy && !uart_start) begin
                    uart_byte <= edge_seen ? 8'h31 : 8'h30;
                    uart_start <= 1'b1;
                    out_state <= 4'd3;
                end
            end
            4'd3: begin
                if (!uart_busy && !uart_start) begin
                    uart_byte <= low_seen ? 8'h31 : 8'h30;
                    uart_start <= 1'b1;
                    out_state <= 4'd4;
                end
            end
            4'd4: begin
                if (!uart_busy && !uart_start) begin
                    uart_byte <= hex_char(edge_count);
                    uart_start <= 1'b1;
                    out_state <= 4'd5;
                end
            end
            4'd5: begin
                if (!uart_busy && !uart_start) begin
                    uart_byte <= hex_char(low_count);
                    uart_start <= 1'b1;
                    out_state <= 4'd6;
                end
            end
            4'd6: begin
                if (!uart_busy && !uart_start) begin
                    uart_byte <= 8'h0A;
                    uart_start <= 1'b1;
                    out_state <= 4'd7;
                end
            end
            4'd7: begin
                if (!uart_busy && !uart_start) begin
                    hb_pending <= 1'b0;
                    edge_seen <= 1'b0;
                    low_seen <= 1'b0;
                    edge_count <= 4'd0;
                    low_count <= 4'd0;
                    out_state <= 4'd0;
                end
            end
            default: begin
                out_state <= 4'd0;
            end
        endcase
    end
end

endmodule
