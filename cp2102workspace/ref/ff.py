import serial

# Set baudrate to 115200 (or change to 230400, 460800, 921600)
ser = serial.Serial('/dev/ttyUSB0', baudrate=9600, timeout=None)

print("Streaming real-time RX bits at high speed. Press Ctrl+C to stop.\n")

try:
    while True:
        raw_byte = ser.read(1)
        if raw_byte:
            # Print the 8 raw bits instantly
            print(f"{raw_byte[0]:08b}")

except KeyboardInterrupt:
    ser.close()
    print("\nStopped.")
