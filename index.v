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
localparam integer CAN_BITRATE = 500_000;
localparam integer UART_BAUD = 115200;

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

obd_can_node #(
    .CLK_HZ(CLK_HZ),
    .CAN_BITRATE(CAN_BITRATE),
    .UART_BAUD(UART_BAUD)
) obd_node (
    .clk(clk_in),
    .reset(reset),
    .can_rx(uart_rx_can),
    .can_tx(can_tx),
    .uart_rx(uart_rx_cp2102),
    .uart_tx(dbg_uart_tx)
);

assign uart_tx_can = can_tx;
assign uart_tx_cp2102_inv = ~dbg_uart_tx;
assign slow_blink_clk_led = cnt[27];
assign unused_led = 1'b0;
assign unused_out = 1'b0;

endmodule
