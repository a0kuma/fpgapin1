import argparse
import serial

BITS = '00111010'


def send_serial(port, baud):
    if serial is None:
        raise RuntimeError('pyserial not installed')
    with serial.Serial(port, baud, timeout=1) as s:
        # infinite loop: send the 8-bit pattern as a single packed byte
        val = int(BITS, 2)
        packed = bytes([val])
        while True:
            s.write(packed)


def main():
    p = argparse.ArgumentParser(description='Send bitstring 00111010 (for loop)')
    p.add_argument('--port', default='/dev/ttyUSB0', help='serial port (e.g. /dev/ttyUSB0). Defaults to /dev/ttyUSB0')
    p.add_argument('--baud', type=int, default=9600, help='baud rate')
    args = p.parse_args()

    if serial is None:
        print('pyserial not installed. Install with: pip install pyserial')
        raise SystemExit(1)

    try:
        send_serial(args.port, args.baud)
    except KeyboardInterrupt:
        print('\nInterrupted by user, exiting')
        raise SystemExit(0)
    except Exception as e:
        print(f'Serial error: {e}')
        raise SystemExit(1)


if __name__ == '__main__':
    main()
