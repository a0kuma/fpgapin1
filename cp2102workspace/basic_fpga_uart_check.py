import argparse
import re
import sys
import time

try:
    import serial
except Exception:
    serial = None


def main():
    parser = argparse.ArgumentParser(description="Send math question to FPGA and validate UART reply")
    parser.add_argument("--port", default="/dev/ttyUSB0", help="serial port (default: /dev/ttyUSB0)")
    parser.add_argument("--baud", type=int, default=9600, help="baud rate")
    parser.add_argument("--a", type=int, default=12, help="first 2-digit number")
    parser.add_argument("--b", type=int, default=34, help="second 2-digit number")
    parser.add_argument("--timeout", type=float, default=5.0, help="read timeout in seconds")
    args = parser.parse_args()

    if serial is None:
        print("pyserial not installed. Install with: pip install pyserial")
        raise SystemExit(1)

    a = max(0, min(99, args.a))
    b = max(0, min(99, args.b))
    question = f"waht is {a:02d} + {b:02d} ?"
    expected = f"the ans is {a + b:03d}."

    print(f"TX: {question}")
    print(f"Expect: {expected}")

    try:
        with serial.Serial(args.port, args.baud, timeout=0.1) as ser:
            ser.reset_input_buffer()
            ser.reset_output_buffer()
            ser.write(question.encode("ascii"))
            ser.flush()

            start = time.monotonic()
            buf = ""
            while time.monotonic() - start < args.timeout:
                data = ser.read(1)
                if not data:
                    continue
                ch = data.decode("ascii", errors="replace")
                buf += ch
                sys.stdout.write(ch)
                sys.stdout.flush()
                if expected in buf:
                    print("\nPASS: received expected answer")
                    return 0

            print("\nFAIL: timeout waiting for expected answer")
            return 1
    except KeyboardInterrupt:
        print("\nInterrupted by user, exiting")
        return 1
    except Exception as exc:
        print(f"Serial error: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
