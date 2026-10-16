#!/usr/bin/env bash
# The Pi's vitals while McFly runs, watched from your computer: a line a
# second with the temperature and throttling, the CPU and GPU clocks, the CPU
# the display and the voice service use, the GPU's work, memory, the fan, and
# the busiest process that isn't McFly (a build or a benchmark heating it).
#
#   display/scripts/pi-perf.sh [user@host] [--interval S] [--count N] [--csv FILE] [-i KEY]
#
#   user@host    the Pi; default $MCFLY_PI, else mcfly.local as your SSH user
#   --interval   seconds between lines (default 1)
#   --count      lines to print, then stop (default: until Ctrl-C)
#   --csv FILE   also write every line, unrounded, to FILE (before/after runs)
#   -i KEY       the SSH key to log in with (default $MCFLY_PI_KEY)
#
# Read-only: one SSH connection runs a small Python program on the Pi that
# reads /proc, /sys and vcgencmd. Nothing is installed or changed there.
#
# The columns:
#   TEMP      the SoC, °C (the Pi 5 slows itself from 80 °C, harder at 85)
#   NOW/EVER  throttling now and since boot: HOT soft temperature limit,
#             CAP CPU clock capped, THR throttled, UV under-voltage
#   ARM V3D   CPU and GPU clocks, MHz (2400 and 960 at full speed on a Pi 5)
#   CPU       all four cores together, % of the machine
#   DISP VOICE  the display app and the voice service, % of one core
#   DISP_MB   the display's memory
#   GPU/s     the GPU's render jobs a second: a frame each, plus one for each
#             cached layer redrawn (the saver idles near 30; Home with its
#             ticker runs at the panel's 60 and more)
#   GPU%      how much of the time the GPU was busy rendering
#   FAN       rpm of a fan on the FAN header ("-": none, or one on the 5 V
#             pins, which always runs flat out)
#   OTHER     the busiest process outside McFly, % of one core
set -euo pipefail

host="${MCFLY_PI:-mcfly.local}"
key="${MCFLY_PI_KEY:-}"
interval=1
count=0
csv=""
while [ $# -gt 0 ]; do
    case "$1" in
        --interval) interval="$2"; shift 2 ;;
        --count) count="$2"; shift 2 ;;
        --csv) csv="$2"; shift 2 ;;
        -i) key="$2"; shift 2 ;;
        -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "pi-perf: unknown option $1 (see --help)" >&2; exit 2 ;;
        *) host="$1"; shift ;;
    esac
done

ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5)
[ -n "$key" ] && ssh_opts+=(-i "$key" -o IdentitiesOnly=yes)

# The table: a header now and then, hot and throttled values marked when
# the output is a terminal.
render() {
    local color=0
    [ -t 1 ] && color=1
    awk -F, -v color="$color" '
        function paint(s, code) { return color ? "\033[" code "m" s "\033[0m" : s }
        function header() {
            printf "%-8s %5s %-11s %-11s %5s %4s %5s %6s %6s %7s %6s %5s %6s %6s  %s\n",
                "TIME", "TEMP", "NOW", "EVER", "ARM", "V3D", "CPU", "DISP", "VOICE", "DISP_MB",
                "GPU/s", "GPU%", "MEM_MB", "FAN", "OTHER"
        }
        NR == 1 { next }   # the CSV header
        {
            if ((NR - 2) % 20 == 0) header()
            temp = sprintf("%5.1f", $2)
            if ($2 >= 80) temp = paint(temp, "31"); else if ($2 >= 70) temp = paint(temp, "33")
            now = sprintf("%-11s", $3); if ($3 != "ok") now = paint(now, "31")
            ever = sprintf("%-11s", $4); if ($4 != "ok") ever = paint(ever, "33")
            other = ($18 == "") ? "-" : sprintf("%s %.0f%%", $18, $19)
            printf "%-8s %s %s %s %5s %4s %4.0f%% %5.0f%% %5.0f%% %7.0f %6.1f %4.0f%% %6.0f %6s  %s\n",
                $1, temp, now, ever, $5, $6, $7, $8, $10, $9, $12, $13, $14, $16, other
            fflush()
        }'
}

remote=$(cat <<'PY'
import glob, os, subprocess, sys, time

interval = float(sys.argv[1]); count = int(sys.argv[2])
tick = os.sysconf("SC_CLK_TCK")
gpu_path = next(iter(glob.glob("/sys/devices/platform/axi/*v3d*/gpu_stats")
                     + glob.glob("/sys/devices/platform/*v3d*/gpu_stats")), None)
fan_path = next(iter(glob.glob("/sys/devices/platform/cooling_fan/hwmon/hwmon*/fan1_input")), None)

def read(path, default=""):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return default

def vc(*args):
    try:
        return subprocess.run(["vcgencmd", *args], capture_output=True, text=True, timeout=2).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""

def mhz(name):
    out = vc("measure_clock", name)   # frequency(0)=1500000000
    return str(round(int(out.split("=")[1]) / 1e6)) if "=" in out else ""

FLAGS = [(3, "HOT"), (1, "CAP"), (2, "THR"), (0, "UV")]
def throttling(shift):
    out = vc("get_throttled")         # throttled=0xe0006
    if "=" not in out:
        return "?"
    bits = int(out.split("=")[1], 16) >> shift
    named = [name for bit, name in FLAGS if bits & (1 << bit)]
    return "+".join(named) if named else "ok"

def cpu_total():
    f = read("/proc/stat").split("\n", 1)[0].split()[1:]
    v = [int(x) for x in f]
    return sum(v), v[3] + v[4]        # all, idle + iowait

def proc_times():
    out = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        s = read(f"/proc/{d}/stat")
        if not s:
            continue
        rest = s[s.rfind(")") + 2:].split()
        out[int(d)] = int(rest[11]) + int(rest[12])   # utime + stime
    return out

def main_pid(unit):
    try:
        pid = subprocess.run(["systemctl", "show", "-p", "MainPID", "--value", unit],
                             capture_output=True, text=True, timeout=2).stdout.strip()
        return int(pid) if pid and pid != "0" else 0
    except (OSError, subprocess.SubprocessError, ValueError):
        return 0

def rss_mb(pid):
    for line in read(f"/proc/{pid}/status").splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1]) / 1024
    return 0

def label(pid):
    # The program and, for an interpreter, what it runs, with the pid: one
    # line, no commas or quotes, short (it is a CSV field and a table cell).
    args = [a for a in read(f"/proc/{pid}/cmdline").split("\0") if a]
    name = os.path.basename(args[0]) if args else read(f"/proc/{pid}/comm").strip()
    if args and name.startswith(("python", "node", "bash", "sh", "perl")) and len(args) > 1:
        rest = args[1:]
        if rest[0] == "-c":
            name += " -c"
        elif rest[0] == "-m" and len(rest) > 1:
            name += " -m " + rest[1]
        else:
            script = next((a for a in rest if not a.startswith("-")), "")
            if script:
                name += " " + os.path.basename(script)
    name = " ".join(name.split()).replace(",", " ").replace('"', "").replace("'", "")
    return f"{name[:28]} [{pid}]"

def gpu():
    jobs = runtime = 0
    for line in read(gpu_path).splitlines() if gpu_path else []:
        f = line.split()
        if f and f[0] == "render":
            jobs, runtime = int(f[2]), int(f[3])
    return jobs, runtime

def mem_used_mb():
    info = {}
    for line in read("/proc/meminfo").splitlines():
        k, v = line.split(":", 1)
        info[k] = int(v.split()[0])
    return (info.get("MemTotal", 0) - info.get("MemAvailable", 0)) / 1024

print("time,temp_c,throttle_now,throttle_since_boot,arm_mhz,v3d_mhz,cpu_pct,display_cpu,display_mb,"
      "voice_cpu,voice_mb,gpu_jobs_s,gpu_busy_pct,mem_used_mb,load1,fan_rpm,display_pid,other,other_cpu", flush=True)
prev_all, prev_idle = cpu_total()
prev_procs = proc_times()
prev_jobs, prev_runtime = gpu()
prev_t = time.monotonic()
n = 0
while count == 0 or n < count:
    time.sleep(interval)
    t = time.monotonic(); dt = t - prev_t; prev_t = t
    all_, idle = cpu_total()
    cpu = 100 * (1 - (idle - prev_idle) / max(1, all_ - prev_all))
    prev_all, prev_idle = all_, idle
    procs = proc_times()
    use = {pid: 100 * (v - prev_procs.get(pid, v)) / (tick * dt) for pid, v in procs.items()}
    prev_procs = procs
    display, voice = main_pid("mcfly-display"), main_pid("mcfly-voice")
    others = [(c, pid) for pid, c in use.items() if pid not in (display, voice, os.getpid())]
    other_cpu, other_pid = max(others) if others else (0, 0)
    jobs, runtime = gpu()
    gpu_jobs = (jobs - prev_jobs) / dt; gpu_busy = 100 * (runtime - prev_runtime) / (dt * 1e9)
    prev_jobs, prev_runtime = jobs, runtime
    temp = int(read("/sys/class/thermal/thermal_zone0/temp", "0") or 0) / 1000
    fan = read(fan_path).strip() if fan_path else "-"
    row = [time.strftime("%H:%M:%S"), f"{temp:.1f}", throttling(0), throttling(16), mhz("arm"), mhz("v3d"),
           f"{cpu:.1f}", f"{use.get(display, 0):.1f}", f"{rss_mb(display):.0f}" if display else "0",
           f"{use.get(voice, 0):.1f}", f"{rss_mb(voice):.0f}" if voice else "0",
           f"{gpu_jobs:.1f}", f"{gpu_busy:.1f}", f"{mem_used_mb():.0f}", read("/proc/loadavg").split()[0],
           fan or "-", str(display),
           label(other_pid) if other_cpu >= 5 else "", f"{other_cpu:.0f}" if other_cpu >= 5 else "0"]
    print(",".join(row), flush=True)
    n += 1
PY
)

run() { ssh "${ssh_opts[@]}" "$host" python3 - "$interval" "$count" <<<"$remote"; }
if [ -n "$csv" ]; then
    run | tee "$csv" | render
else
    run | render
fi
