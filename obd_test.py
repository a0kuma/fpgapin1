#!/usr/bin/env python3
import argparse
import re
import sys
import time

try:
    import serial
except ImportError:
    print("pyserial not installed. Install with: pip install pyserial")
    sys.exit(1)


def read_until_prompt(ser, timeout_s):
    end_time = time.time() + timeout_s
    buf = b""
    while time.time() < end_time:
        chunk = ser.read(1)
        if chunk:
            buf += chunk
            if b">" in buf:
                break
    return buf.decode("ascii", errors="ignore")


def send_cmd(ser, cmd, timeout_s):
    ser.reset_input_buffer()
    ser.write((cmd + "\r").encode("ascii"))
    return read_until_prompt(ser, timeout_s)


def parse_pid(resp, pid_hex):
    tokens = re.findall(r"[0-9A-F]{2}", resp.upper())
    pid = pid_hex.upper()
    for i in range(len(tokens) - 1):
        if tokens[i] == "41" and tokens[i + 1] == pid:
            return tokens[i + 2 :]
    return []


def open_port(port, baud):
    ser = serial.Serial(port, baudrate=baud, timeout=0.1)
    time.sleep(0.1)
    ser.reset_input_buffer()
    return ser


def try_baud_list(port, baud_list, timeout_s):
    for baud in baud_list:
        try:
            ser = open_port(port, baud)
        except Exception as exc:
            print(f"open {port} @ {baud} failed: {exc}")
            continue
        resp = send_cmd(ser, "ATZ", timeout_s)
        if "ELM" in resp or "OK" in resp or ">" in resp:
            return ser, baud, resp
        ser.close()
    return None, None, ""


def main():
    parser = argparse.ArgumentParser(description="ELM327 OBD test for PID 0C/0D")
    parser.add_argument("--port", default="/dev/ttyUSB0", help="ELM327 serial port")
    parser.add_argument("--baud", type=int, default=0, help="Baud rate (0 = auto)")
    parser.add_argument("--timeout", type=float, default=2.0, help="Read timeout seconds")
    parser.add_argument("--protocol", default="6", help="ELM327 protocol (6=CAN 11/500)")
    args = parser.parse_args()

    if args.baud == 0:
        baud_list = [38400, 9600, 115200]
    else:
        baud_list = [args.baud]

    ser, baud, resp = try_baud_list(args.port, baud_list, args.timeout)
    if not ser:
        print("Failed to connect to ELM327. Try --baud and --port.")
        sys.exit(1)

    print(f"Connected on {args.port} @ {baud}")
    if resp.strip():
        print(resp.strip())

    for cmd in ["ATE0", "ATL0", "ATS0", "ATH0", f"ATSP{args.protocol}"]:
        send_cmd(ser, cmd, args.timeout)

    resp_rpm = send_cmd(ser, "010C", args.timeout)
    resp_spd = send_cmd(ser, "010D", args.timeout)

    print("Raw RPM response:")
    print(resp_rpm.strip())
    print("Raw speed response:")
    print(resp_spd.strip())

    rpm_bytes = parse_pid(resp_rpm, "0C")
    spd_bytes = parse_pid(resp_spd, "0D")

    if len(rpm_bytes) >= 2:
        rpm_raw = int(rpm_bytes[0], 16) * 256 + int(rpm_bytes[1], 16)
        rpm = rpm_raw / 4.0
        print(f"RPM: {rpm:.1f}")
    else:
        print("RPM: no data")

    if len(spd_bytes) >= 1:
        spd = int(spd_bytes[0], 16)
        print(f"Speed: {spd} km/h")
    else:
        print("Speed: no data")

    ser.close()


if __name__ == "__main__":
    main()
