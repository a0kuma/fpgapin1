import re
import threading
import subprocess
from pathlib import Path
import tkinter as tk
from tkinter import ttk, messagebox
from tkinter.scrolledtext import ScrolledText

ROOT_DIR = Path(__file__).resolve().parent
INDEX_V = ROOT_DIR / "index.v"
UCF = ROOT_DIR / "blink.ucf"
XISE = ROOT_DIR / "assume_board_is_nexys3.xise"
BURN_CMD = ROOT_DIR / "burn.cmd"


def parse_ucf():
    if not UCF.exists():
        raise FileNotFoundError(f"Missing {UCF}")

    lines = UCF.read_text().splitlines()
    clk_line = next((l for l in lines if l.startswith('NET "clk_in"')), None)
    led0_line = next((l for l in lines if l.startswith('NET "led<0>"')), None)
    led1_line = next((l for l in lines if l.startswith('NET "led<1>"')), None)

    pin_re = re.compile(r'NET "pin_out\[(\d+)\]"\s+LOC\s*=\s*"([^"]+)"')
    pins = {}
    for line in lines:
        m = pin_re.search(line)
        if m:
            pins[int(m.group(1))] = m.group(2)

    if not pins:
        raise ValueError("No pin_out entries found in blink.ucf")

    pin_list = [pins[i] for i in sorted(pins)]
    return clk_line, led0_line, led1_line, pin_list


def infer_pin_states(pin_count):
    if not INDEX_V.exists():
        return [False] * pin_count

    text = INDEX_V.read_text()

    m = re.search(r"PIN_MASK\s*=\s*(\d+)'b([01_]+)", text)
    if not m:
        m = re.search(r"assign\s+pin_out\s*=\s*(\d+)'b([01_]+)", text)

    if m:
        bits = m.group(2).replace("_", "")
        if len(bits) == pin_count:
            return [bits[-1 - i] == "1" for i in range(pin_count)]

    if "{PIN_COUNT{1'b1}}" in text:
        return [True] * pin_count
    if "{PIN_COUNT{1'b0}}" in text:
        return [False] * pin_count

    return [False] * pin_count


def write_verilog(pin_states):
    pin_count = len(pin_states)
    bits = "".join("1" if pin_states[i] else "0" for i in range(pin_count - 1, -1, -1))

    text = (
        "module clk_probe #(\n"
        f"    parameter integer PIN_COUNT = {pin_count}\n"
        ")(\n"
        "    input  wire clk_in,\n"
        "    output wire [PIN_COUNT-1:0] pin_out,\n"
        "    output wire [1:0] led\n"
        ");\n\n"
        "reg [31:0] cnt = 32'd0;\n\n"
        "always @(posedge clk_in) begin\n"
        "    cnt <= cnt + 1'b1;\n"
        "end\n\n"
        f"localparam [PIN_COUNT-1:0] PIN_MASK = {pin_count}'b{bits};\n\n"
        "assign pin_out = PIN_MASK;\n"
        "assign led[0] = cnt[27];\n"
        "assign led[1] = 1'b0;\n\n"
        "endmodule\n"
    )

    INDEX_V.write_text(text)


def write_ucf(clk_line, led0_line, led1_line, pin_list):
    lines = []
    lines.append(clk_line or 'NET "clk_in" LOC = "U10" | IOSTANDARD = LVCMOS33;')
    lines.append("")
    lines.append(led0_line or 'NET "led<0>" LOC = "D11" | IOSTANDARD = LVCMOS33 | DRIVE = 2 | SLEW = SLOW;')
    lines.append(led1_line or 'NET "led<1>" LOC = "C11" | IOSTANDARD = LVCMOS33 | DRIVE = 2 | SLEW = SLOW;')
    lines.append("")

    for idx, pin in enumerate(pin_list):
        lines.append(f'NET "pin_out[{idx}]" LOC = "{pin}" | IOSTANDARD = LVCMOS33;')

    UCF.write_text("\n".join(lines) + "\n")


def write_burn_cmd():
    text = (
        "setMode -bs\n"
        "setCable -p auto\n"
        "Identify\n"
        "assignFile -p 1 -file clk_probe.bit\n"
        "Program -p 1\n"
        "quit\n"
    )
    BURN_CMD.write_text(text)


def run_bash(cmd, log_fn):
    proc = subprocess.run(
        ["/bin/bash", "-lc", cmd],
        cwd=str(ROOT_DIR),
        capture_output=True,
        text=True,
    )
    output = proc.stdout + proc.stderr
    if proc.returncode != 0:
        output += f"\n[exit {proc.returncode}]\n"
    log_fn(output)


class PinGui(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("FPGA Pin Output GUI")
        self.geometry("980x720")

        clk_line, led0_line, led1_line, pin_list = parse_ucf()
        self.clk_line = clk_line
        self.led0_line = led0_line
        self.led1_line = led1_line
        self.pin_list = pin_list
        self.pin_count = len(pin_list)

        states = infer_pin_states(self.pin_count)
        self.vars = [tk.BooleanVar(value=states[i]) for i in range(self.pin_count)]

        top_frame = ttk.Frame(self)
        top_frame.pack(fill="x", padx=10, pady=8)

        ttk.Label(top_frame, text=f"Pins: {self.pin_count}").pack(side="left")

        btn_frame = ttk.Frame(top_frame)
        btn_frame.pack(side="right")

        ttk.Button(btn_frame, text="Apply (write .v/.ucf)", command=self.apply_files).pack(side="left", padx=4)
        ttk.Button(btn_frame, text="Compile", command=self.compile_only).pack(side="left", padx=4)
        ttk.Button(btn_frame, text="Burn", command=self.burn_only).pack(side="left", padx=4)
        ttk.Button(btn_frame, text="Compile + Burn", command=self.compile_and_burn).pack(side="left", padx=4)

        container = ttk.Frame(self)
        container.pack(fill="both", expand=True, padx=10, pady=8)

        canvas = tk.Canvas(container)
        scrollbar = ttk.Scrollbar(container, orient="vertical", command=canvas.yview)
        self.scrollable = ttk.Frame(canvas)

        self.scrollable.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all")),
        )

        canvas.create_window((0, 0), window=self.scrollable, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        self._build_checkboxes()

        self.log = ScrolledText(self, height=12, state="disabled")
        self.log.pack(fill="both", expand=False, padx=10, pady=8)

    def _build_checkboxes(self):
        cols = 6
        for i, pin in enumerate(self.pin_list):
            row = i // cols
            col = i % cols
            label = f"[{i}] {pin}"
            cb = ttk.Checkbutton(self.scrollable, text=label, variable=self.vars[i])
            cb.grid(row=row, column=col, sticky="w", padx=6, pady=2)

    def _append_log(self, msg):
        self.log.configure(state="normal")
        self.log.insert("end", msg + "\n")
        self.log.see("end")
        self.log.configure(state="disabled")

    def apply_files(self):
        pin_states = [v.get() for v in self.vars]
        write_verilog(pin_states)
        write_ucf(self.clk_line, self.led0_line, self.led1_line, self.pin_list)
        self._append_log("Wrote index.v and blink.ucf")

    def _run_threaded(self, cmd):
        def worker():
            run_bash(cmd, lambda out: self.after(0, self._append_log, out))

        threading.Thread(target=worker, daemon=True).start()

    def compile_only(self):
        self.apply_files()
        cmd = (
            "source /opt/Xilinx/14.7/ISE_DS/settings64.sh\n"
            "xtclsh <<'EOF'\n"
            "project open assume_board_is_nexys3.xise\n"
            "process run \"Synthesize - XST\"\n"
            "process run \"Implement Design\"\n"
            "process run \"Generate Programming File\"\n"
            "project close\n"
            "exit\n"
            "EOF\n"
        )
        self._append_log("Starting compile...")
        self._run_threaded(cmd)

    def burn_only(self):
        self.apply_files()
        write_burn_cmd()
        cmd = (
            "source /opt/Xilinx/14.7/ISE_DS/settings64.sh\n"
            "impact -batch burn.cmd\n"
        )
        self._append_log("Starting burn...")
        self._run_threaded(cmd)

    def compile_and_burn(self):
        self.apply_files()
        write_burn_cmd()
        cmd = (
            "source /opt/Xilinx/14.7/ISE_DS/settings64.sh\n"
            "xtclsh <<'EOF'\n"
            "project open assume_board_is_nexys3.xise\n"
            "process run \"Synthesize - XST\"\n"
            "process run \"Implement Design\"\n"
            "process run \"Generate Programming File\"\n"
            "project close\n"
            "exit\n"
            "EOF\n"
            "impact -batch burn.cmd\n"
        )
        self._append_log("Starting compile + burn...")
        self._run_threaded(cmd)


if __name__ == "__main__":
    try:
        app = PinGui()
        app.mainloop()
    except Exception as exc:
        messagebox.showerror("Error", str(exc))
