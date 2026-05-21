module obd_can_node #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer CAN_BITRATE = 500_000,
    parameter integer UART_BAUD = 115200
) (
    input  wire clk,
    input  wire reset,
    input  wire can_rx,
    output wire can_tx,
    input  wire uart_rx,
    output wire uart_tx
);

localparam [10:0] OBD_ID_FUNC = 11'h7DF;
localparam [10:0] OBD_ID_PHYS = 11'h7E0;
localparam [10:0] OBD_ID_RESP = 11'h7E8;

localparam [15:0] RPM_RAW = 16'd12000; // 3000 RPM * 4
localparam [7:0] SPEED_KPH = 8'd88;

wire rx_valid;
wire [10:0] rx_id;
wire [3:0] rx_dlc;
wire [63:0] rx_data;

reg tx_start = 1'b0;
reg [10:0] tx_id = 11'd0;
reg [3:0] tx_dlc = 4'd0;
reg [63:0] tx_data = 64'd0;
wire tx_busy;
wire tx_done;

reg resp_pending = 1'b0;
reg [7:0] resp_pid = 8'd0;

wire [7:0] rx_b0 = rx_data[63:56];
wire [7:0] rx_b1 = rx_data[55:48];
wire [7:0] rx_b2 = rx_data[47:40];

wire is_obd_id = (rx_id == OBD_ID_FUNC) || (rx_id == OBD_ID_PHYS);
wire is_obd_req = is_obd_id && (rx_dlc >= 4'd3) && (rx_b0 == 8'h02) && (rx_b1 == 8'h01);
wire is_pid_supported = (rx_b2 == 8'h0C) || (rx_b2 == 8'h0D);

wire [7:0] rpm_a = RPM_RAW[15:8];
wire [7:0] rpm_b = RPM_RAW[7:0];

reg dbg_start = 1'b0;
reg [7:0] dbg_byte = 8'd0;
wire dbg_busy;
reg [1:0] dbg_state = 2'd0;
reg dbg_pending = 1'b0;
reg [7:0] dbg_pid = 8'd0;

can_simple_controller #(
    .CLK_HZ(CLK_HZ),
    .CAN_BITRATE(CAN_BITRATE)
) can_core (
    .clk(clk),
    .reset(reset),
    .can_rx(can_rx),
    .can_tx(can_tx),
    .tx_start(tx_start),
    .tx_id(tx_id),
    .tx_dlc(tx_dlc),
    .tx_data(tx_data),
    .tx_busy(tx_busy),
    .tx_done(tx_done),
    .rx_valid(rx_valid),
    .rx_id(rx_id),
    .rx_dlc(rx_dlc),
    .rx_data(rx_data)
);

uart_tx #(
    .CLK_HZ(CLK_HZ),
    .BAUD(UART_BAUD)
) dbg_uart (
    .clk(clk),
    .reset(reset),
    .tx_start(dbg_start),
    .tx_data(dbg_byte),
    .tx_busy(dbg_busy),
    .tx_line(uart_tx)
);

always @(posedge clk) begin
    if (reset) begin
        resp_pending <= 1'b0;
        resp_pid <= 8'd0;
    end else begin
        if (rx_valid && is_obd_req && is_pid_supported) begin
            if (!resp_pending) begin
                resp_pending <= 1'b1;
                resp_pid <= rx_b2;
            end
        end

        tx_start <= 1'b0;
        if (resp_pending && !tx_busy) begin
            tx_id <= OBD_ID_RESP;
            tx_dlc <= 4'd8;
            if (resp_pid == 8'h0C) begin
                tx_data <= {8'h04, 8'h41, 8'h0C, rpm_a, rpm_b, 8'h00, 8'h00, 8'h00};
            end else if (resp_pid == 8'h0D) begin
                tx_data <= {8'h03, 8'h41, 8'h0D, SPEED_KPH, 8'h00, 8'h00, 8'h00, 8'h00};
            end else begin
                tx_data <= 64'd0;
            end
            tx_start <= 1'b1;
            resp_pending <= 1'b0;
        end
    end
end

always @(posedge clk) begin
    if (reset) begin
        dbg_state <= 2'd0;
        dbg_pending <= 1'b0;
        dbg_pid <= 8'd0;
        dbg_start <= 1'b0;
        dbg_byte <= 8'd0;
    end else begin
        dbg_start <= 1'b0;
        if (rx_valid && is_obd_req && is_pid_supported) begin
            dbg_pending <= 1'b1;
            dbg_pid <= rx_b2;
        end

        case (dbg_state)
            2'd0: begin
                if (dbg_pending && !dbg_busy) begin
                    dbg_byte <= 8'h52; // 'R'
                    dbg_start <= 1'b1;
                    dbg_state <= 2'd1;
                end
            end
            2'd1: begin
                if (!dbg_busy) begin
                    dbg_byte <= dbg_pid;
                    dbg_start <= 1'b1;
                    dbg_state <= 2'd2;
                end
            end
            2'd2: begin
                if (!dbg_busy) begin
                    dbg_byte <= 8'h0A;
                    dbg_start <= 1'b1;
                    dbg_state <= 2'd0;
                    dbg_pending <= 1'b0;
                end
            end
            default: begin
                dbg_state <= 2'd0;
            end
        endcase
    end
end

endmodule
