#!/usr/bin/env python3 -I
"""Smoke test: drives the real `ytm` binary through a pseudo-terminal.

Searches, plays, pauses, queues, skips, removes and quits, asserting on the
rendered screen. Needs network access, mpv and yt-dlp, and plays audio.

    just smoke
"""
import os, pty, select, time, sys, struct, fcntl, termios, subprocess, re, glob

binary = sys.argv[1]
cols, rows = 140, 36
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
errpath = os.path.join(os.environ.get("TMPDIR", "/tmp"), "ytm-smoke-stderr.txt")
err = open(errpath, "wb")
proc = subprocess.Popen([binary], stdin=slave, stdout=slave, stderr=err, preexec_fn=os.setsid,
                        env=dict(os.environ, TERM="xterm-256color"), close_fds=True)
os.close(slave)

# Minimal terminal emulator: cursor moves, clear, printable text. SGR ignored.
grid = [[" "] * cols for _ in range(rows)]
cur = [0, 0]
pending = ""
raw = b""
esc = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")

def apply(text):
    global pending
    pending += text
    i = 0
    out = []
    while i < len(pending):
        ch = pending[i]
        if ch == "\x1b":
            m = esc.match(pending, i)
            if not m:
                if len(pending) - i < 12:  # incomplete sequence, wait for more
                    break
                i += 1
                continue
            params, final = m.group(1), m.group(2)
            if final == "H":
                parts = [p for p in params.split(";") if p]
                r = int(parts[0]) - 1 if parts else 0
                c = int(parts[1]) - 1 if len(parts) > 1 else 0
                cur[0], cur[1] = max(0, min(r, rows - 1)), max(0, min(c, cols - 1))
            elif final == "J":
                for row in grid:
                    row[:] = [" "] * cols
            i = m.end()
            continue
        if ch in "\r\n":
            i += 1
            continue
        if cur[1] < cols:
            grid[cur[0]][cur[1]] = ch
        cur[1] += 1
        i += 1
    pending = pending[i:]

def pump(seconds):
    global raw
    end = time.time() + seconds
    while time.time() < end:
        r, _, _ = select.select([master], [], [], 0.1)
        if master in r:
            try:
                data = os.read(master, 65536)
            except OSError:
                return
            if not data:
                return
            raw += data
            apply(data.decode("utf-8", "replace"))

def screen():
    return "\n".join("".join(row) for row in grid)

def send(keys, wait):
    os.write(master, keys.encode())
    pump(wait)

def check(label, cond):
    print(("PASS " if cond else "FAIL ") + label)
    return cond

ok = True
pump(2.0)
s = screen()
ok &= check("initial frame: search bar, filter tabs, queue header", "type to search" in s and "1 Songs" in s and "2 Artists" in s and "Queue" in s)
ok &= check("entered alternate screen", b"\x1b[?1049h" in raw)
send("/", 0.3)
send("daft punk", 0.3)
ok &= check("query echoed with cursor", "/ daft punk▏" in screen())
send("\r", 6.0)
s = screen()
ok &= check("search results rendered", "Songs · daft punk (20)" in s and "Daft Punk" in s)
ok &= check("first result selected row visible", "End of Line" in s)
def result_title(row):
    """Title of the result shown on screen row `row` (first result is row 3)."""
    line = "".join(grid[row]).split("│")[0]
    return line.strip().split(" — ")[0].split("  [")[0]

first_title = result_title(3)
second_title = result_title(4)
ok &= check("read two result titles (%r, %r)" % (first_title[:30], second_title[:30]), bool(first_title and second_title))
send("j", 0.3)
send("\r", 15.0)
s = screen()
ok &= check("now playing shows the second result", ("▶ " + second_title[:30]) in s)
time_match = re.search(r"\b0:(\d\d)/\d+:\d\d", s)
ok &= check("elapsed time advanced (%s)" % (time_match.group(0) if time_match else "none"), time_match is not None and int(time_match.group(1)) >= 5)
ok &= check("queue pane shows playing marker", ("▶   1 " + second_title[:20]) in s)
mpv_running = subprocess.run(["pgrep", "-f", "input-ipc-server=.*ytm-%d" % proc.pid], capture_output=True).returncode == 0
ok &= check("mpv process running for this ytm pid", mpv_running)
send(" ", 1.0)
ok &= check("pause marker shown", ("‖ " + second_title[:30]) in screen())
send(" ", 0.5)
ok &= check("resumed", ("▶ " + second_title[:30]) in screen())
send("k", 0.3)
send("a", 1.0)
s = screen()
ok &= check("add to queue message and count", ("Added “" + first_title[:20]) in s and "Queue (2)" in s)
send("n", 10.0)
s = screen()
ok &= check("next plays the added track", ("▶ " + first_title[:30]) in s and ("▶   2 " + first_title[:20]) in s)
send("\t", 0.3)
send("k", 0.3)
send("x", 0.5)
ok &= check("removed a queue entry", "Queue (1)" in screen())
send("r", 0.3)
ok &= check("radio toggled off", "radio off" in screen())
send("q", 2.0)
rc = proc.wait(timeout=5)
ok &= check("exit code 0 on q (got %s)" % rc, rc == 0)
ok &= check("left alternate screen and showed cursor", b"\x1b[?1049l" in raw and b"\x1b[?25h" in raw)
time.sleep(1.5)
mpv_after = subprocess.run(["pgrep", "-f", "input-ipc-server=.*ytm-%d" % proc.pid], capture_output=True).returncode == 0
ok &= check("mpv terminated after quit", not mpv_after)
leftovers = glob.glob(os.path.join(os.environ.get("TMPDIR", "/tmp"), "ytm-%d.sock" % proc.pid))
ok &= check("socket file removed", not leftovers)
stderr = open(errpath, "rb").read()
ok &= check("no stderr output (%d bytes)" % len(stderr), len(stderr) == 0)
if not ok:
    print("---- final screen ----")
    print(screen())
    print("---- stderr ----")
    print(stderr.decode("utf-8", "replace")[:2000])
sys.exit(0 if ok else 1)
