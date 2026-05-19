import argparse
import sys

try:
    import serial
except Exception:
    serial = None


def main():
    parser = argparse.ArgumentParser(description="Read UART from CP2102 and print characters")
    parser.add_argument("--port", default="/dev/ttyUSB0", help="serial port (default: /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=9600, help="baud rate")
    args = parser.parse_args()

    if serial is None:
        print("pyserial not installed. Install with: pip install pyserial")
        raise SystemExit(1)

    try:
        with serial.Serial(args.port, args.baud, timeout=1) as ser:
            while True:
                data = ser.read(1)
                if not data:
                    continue
                ch = data.decode("ascii", errors="replace")
                sys.stdout.write(ch)
                sys.stdout.flush()
    except KeyboardInterrupt:
        print("\nInterrupted by user, exiting")
        raise SystemExit(0)
    except Exception as exc:
        print(f"Serial error: {exc}")
        raise SystemExit(1)


if __name__ == "__main__":
    main()
