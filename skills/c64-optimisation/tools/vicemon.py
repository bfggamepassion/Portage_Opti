"""Drive x64sc (VICE 3.10) through its text remote monitor: run in warp, dump RAM / I/O / screenshots,
patch memory, fake the joystick, capture an execution trace for prof.py.

    v = Vice(["-autostart", "game.d64"])
    v.run_to(60e6); v.dump("dumps/title")            # .ram .io .reg .png
    v.joy_auto(0x02a7); v.joy_cell(0x10)             # press fire
    v.run_for(2e6); v.history("dumps/play.chis")     # then: prof.py dumps/play.chis
    v.quit()

Notes learnt the hard way:
- without a visible window VICE stalls at normal speed: warp must be forced ("warp on") after autostart;
- VICE keeps running when the monitor connection is closed (detach), and the stopwatch wraps at 2^32;
- the binary monitor's "joyport set" had no effect here, hence the joystick fakes below.
"""
import socket, subprocess, time, os, re

VICE = os.path.expandvars(r"%LOCALAPPDATA%\VICE\GTK3VICE-3.10-win64\bin\x64sc.exe")


def _p(path):
    return os.path.abspath(path).replace("\\", "/")


class Vice:
    def __init__(self, args=None, port=6510, boot_wait=5):
        """args=None: attach to an x64sc already started by an earlier Vice(...).detach()."""
        self.cell = 0x0002
        self.p = None
        if args is not None:
            cmd = [VICE, "-default", "-sounddev", "dummy", "-warp", "-monchislines", "200000",
                   "-remotemonitor", "-remotemonitoraddress", f"ip4://127.0.0.1:{port}"]
            self.p = subprocess.Popen(cmd + args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(boot_wait)
        for _ in range(40):                      # VICE may take a while to open its monitor
            try:
                self.s = socket.create_connection(("127.0.0.1", port), timeout=5)
                if "ADDR" in self.c("r", 1.0):
                    break
                self.s.close()
            except OSError:
                pass
            time.sleep(0.5)
        self.c("warp on")

    def _rd(self, wait=0.6):
        self.s.settimeout(wait)
        b = b''
        try:
            while True:
                c = self.s.recv(65536)
                if not c:
                    break
                b += c
        except socket.timeout:
            pass
        return b.decode('latin1')

    def c(self, text, wait=0.6):
        """Send a monitor command (this pauses the emulation), return its output."""
        self.s.sendall(text.encode() + b"\n")
        return self._rd(wait)

    def go(self):
        self.s.sendall(b"x\n")

    def regs(self):
        out = self.c("r")
        m = re.search(r"\.;([0-9a-f]{4}) (\w\w) (\w\w) (\w\w) (\w\w) (\w\w) (\w\w) (\d+) (\d+) (\d+)\s+(\d+)", out)
        d = {n: int(m.group(i + 1), 16) for i, n in enumerate(('pc', 'a', 'x', 'y', 'sp', 'p0', 'p1'))}
        d['line'], d['cyc'], d['clk'] = int(m.group(9)), int(m.group(10)), int(m.group(11))
        return d

    def run_to(self, clk):
        """Run in warp until the stopwatch reaches clk cycles (overshoots by a few frames)."""
        while True:
            r = self.regs()
            if r['clk'] >= clk:
                return r
            self.c("warp on", 0.2)
            self.go()
            time.sleep(min(2.0, max(0.1, (clk - r['clk']) / 12e6)))

    def run_for(self, cycles):
        return self.run_to(self.regs()['clk'] + cycles)

    def dump(self, prefix):
        """prefix.ram (64K RAM), prefix.io ($D000-$DFFF registers), prefix.reg, prefix.png"""
        p = _p(prefix)
        self.c("bank ram")
        self.c(f'save "{p}.ram" 0 0000 ffff', 1.0)
        self.c("bank io")
        self.c(f'save "{p}.io" 0 d000 dfff', 1.0)
        self.c("bank cpu")
        open(p + ".reg", "w").write(repr(self.regs()))
        self.shot(p + ".png")

    def shot(self, path):
        self.c('screenshot "%s" 2' % _p(path), 1.0)

    def disk(self, path):
        self.c('attach "%s" 8' % _p(path), 1.0)

    def poke(self, addr, data):
        self.c("bank ram")
        self.c(f"> {addr:04x} " + " ".join(f"{b:02x}" for b in data))
        self.c("bank cpu")

    # --- joystick (port 2). value bits: 0 up, 1 down, 2 left, 3 right, 4 fire; 1 = pressed ---

    def joy(self, value, base=0x7f):
        """Drive CIA1 port A low ourselves. Only works while the game leaves $DC00/$DC02 alone."""
        self.c("bank io")
        self.c("> dc02 ff")
        self.c(f"> dc00 {base & ~value & 0xff:02x}")
        self.c("bank cpu")

    def joy_patch(self, sites, cell=0x0002):
        """Redirect each absolute read of $DC00 at `sites` to a RAM cell we control, then use joy_cell().
        Pick a cell the program does not use: $02 on a stock machine, $02A7-$02FF otherwise. Never $01xx
        (decrunchers live there), and never write the cell while something is decrunching."""
        self.cell = cell
        for a in sites:
            self.poke(a + 1, [cell & 255, cell >> 8])
        self.joy_cell(0)

    def joy_auto(self, cell=0x0002, tmp="_scan"):
        """joy_patch on every absolute read of $DC00 found in RAM right now. Returns the addresses."""
        self.dump(tmp)
        ram = open(_p(tmp) + ".ram", "rb").read()[2:]
        sites = [i for i in range(0xfffd) if ram[i + 1] == 0x00 and ram[i + 2] == 0xdc
                 and ram[i] in (0xad, 0xae, 0xac, 0x2c, 0x2d, 0x4d, 0xcd)]
        self.joy_patch(sites, cell)
        return sites

    def joy_cell(self, value):
        self.poke(self.cell, [~value & 0xff])

    def history(self, path, n=120000):
        """Save the last n executed instructions (VICE `chis`), cycle-stamped: input of prof.py.
        120 000 instructions is about 20 PAL frames."""
        self.s.sendall(f"chis {n}\n".encode())
        self.s.settimeout(4)
        out = []
        try:
            while True:
                c = self.s.recv(1 << 20)
                if not c:
                    break
                out.append(c)
        except socket.timeout:
            pass
        open(path, "wb").write(b"".join(out))

    def detach(self):
        """Close our connection (the emulator carries on); reconnect later with Vice()."""
        self.s.close()

    def quit(self):
        try:
            self.s.sendall(b"quit\n")
        except OSError:
            pass
        time.sleep(0.5)
        if self.p:
            try:
                self.p.wait(3)
            except subprocess.TimeoutExpired:
                self.p.kill()


def load(prefix):
    """(ram[65536], io[4096]) from a dump made by Vice.dump (strips the 2-byte PRG headers)."""
    return open(prefix + ".ram", "rb").read()[2:], open(prefix + ".io", "rb").read()[2:]
