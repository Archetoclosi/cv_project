"""
Sensor Interpreter
Legge log Flutter nel formato:
    flutter: SENSOR|timestamp|A:x,y,z|G:x,y,z|M:x,y,z
e stampa in tempo reale la posizione del telefono e le variazioni dei sensori.

Uso:
    python imu_interpreter.py <file.txt>
    python imu_interpreter.py <file.txt> --follow   # segue il file in tempo reale (come tail -f)
"""

import sys
import re
import math
import time
import argparse
from collections import deque


# ─────────────────────────────────────────────
#  SOGLIE CONFIGURABILI
# ─────────────────────────────────────────────
GRAVITY = 9.81

# Accelerometro
STILL_ACCEL_VAR   = 0.08   # varianza sotto cui il telefono è fermo
SHAKE_ACCEL_VAR   = 2.5    # varianza sopra cui è agitato

# Giroscopio
STILL_GYRO_VAR    = 0.005
SHAKE_GYRO_MAG    = 3.0    # rad/s

# Magnetometro
MAG_SLOW_DELTA    = 5.0    # variazione lenta  (µT/s)
MAG_FAST_DELTA    = 30.0   # variazione veloce

# Finestra mobile (campioni)
WINDOW = 20


# ─────────────────────────────────────────────
#  PARSING
# ─────────────────────────────────────────────
LOG_RE = re.compile(
    r"SENSOR\|(\d+)\|A:([-\d.]+),([-\d.]+),([-\d.]+)\|G:([-\d.]+),([-\d.]+),([-\d.]+)\|M:([-\d.]+),([-\d.]+),([-\d.]+)"
)

def parse_line(line):
    m = LOG_RE.search(line)
    if not m:
        return None
    ts = int(m.group(1))
    ax, ay, az = float(m.group(2)), float(m.group(3)), float(m.group(4))
    gx, gy, gz = float(m.group(5)), float(m.group(6)), float(m.group(7))
    mx, my, mz = float(m.group(8)), float(m.group(9)), float(m.group(10))
    return ts, (ax, ay, az), (gx, gy, gz), (mx, my, mz)


# ─────────────────────────────────────────────
#  MATEMATICA
# ─────────────────────────────────────────────
def variance(values):
    if len(values) < 2:
        return 0.0
    mean = sum(values) / len(values)
    return sum((v - mean) ** 2 for v in values) / len(values)

def magnitude(x, y, z):
    return math.sqrt(x*x + y*y + z*z)

def pitch_roll(ax, ay, az):
    pitch = math.degrees(math.atan2(ay, math.sqrt(ax*ax + az*az)))
    roll  = math.degrees(math.atan2(-ax, az))
    return pitch, roll


# ─────────────────────────────────────────────
#  INTERPRETAZIONE POSIZIONE
# ─────────────────────────────────────────────
def interpret_orientation(ax, ay, az):
    """
    Restituisce (label, emoji) in base all'asse dominante dell'accelerazione,
    con pitch e roll inclusi nell'etichetta.
    """
    absx, absy, absz = abs(ax), abs(ay), abs(az)
    dominant = max(absx, absy, absz)

    pitch, roll = pitch_roll(ax, ay, az)

    if dominant == absz:
        if az > 0:
            base = "Poggiato schermo in su (face up)"
        else:
            base = "Poggiato schermo in giù (face down)"
        label = f"{base}  |  pitch {pitch:+.1f}°  roll {roll:+.1f}°"
        emoji = "📲" if az > 0 else "🔄"
    elif dominant == absy:
        if ay > 0:
            base = "In piedi verticale (portrait)"
        else:
            base = "In piedi capovolto (portrait flip)"
        label = f"{base}  |  pitch {pitch:+.1f}°  roll {roll:+.1f}°"
        emoji = "📱" if ay > 0 else "🙃"
    else:
        if ax > 0:
            base = "Landscape sinistro"
        else:
            base = "Landscape destro"
        label = f"{base}  |  pitch {pitch:+.1f}°  roll {roll:+.1f}°"
        emoji = "◀️" if ax > 0 else "▶️"

    return label, emoji

def interpret_motion(accel_window, gyro_window):
    ax_list = [s[0] for s in accel_window]
    ay_list = [s[1] for s in accel_window]
    az_list = [s[2] for s in accel_window]
    gx_list = [s[0] for s in gyro_window]
    gy_list = [s[1] for s in gyro_window]
    gz_list = [s[2] for s in gyro_window]

    a_var = (variance(ax_list) + variance(ay_list) + variance(az_list)) / 3
    g_mag = magnitude(
        sum(gx_list)/len(gx_list),
        sum(gy_list)/len(gy_list),
        sum(gz_list)/len(gz_list)
    )

    if a_var > SHAKE_ACCEL_VAR or g_mag > SHAKE_GYRO_MAG:
        return "Scosso / mosso velocemente", "🤳", a_var
    elif a_var < STILL_ACCEL_VAR:
        return "Fermo", "🛑", a_var
    else:
        return "In movimento", "🏃", a_var

def interpret_mag_speed(mag_deltas):
    """
    mag_deltas: lista di delta |M(t) - M(t-1)| / dt  (µT/s)
    """
    if not mag_deltas:
        return "N/D", "❓"
    avg = sum(mag_deltas) / len(mag_deltas)
    if avg < MAG_SLOW_DELTA:
        return f"Magnetometro stabile ({avg:.1f} µT/s)", "🧲"
    elif avg < MAG_FAST_DELTA:
        return f"Magnetometro in variazione ({avg:.1f} µT/s)", "🔁"
    else:
        return f"Magnetometro varia velocemente! ({avg:.1f} µT/s)", "⚡"


# ─────────────────────────────────────────────
#  STAMPA
# ─────────────────────────────────────────────
COLORS = {
    "reset":  "\033[0m",
    "bold":   "\033[1m",
    "cyan":   "\033[96m",
    "green":  "\033[92m",
    "yellow": "\033[93m",
    "red":    "\033[91m",
    "grey":   "\033[90m",
}

def c(text, color):
    return f"{COLORS.get(color,'')}{text}{COLORS['reset']}"

def print_state(sample_num, ts, orient_label, orient_emoji,
                motion_label, motion_emoji,
                mag_label, mag_emoji,
                pitch, roll, accel_var,
                prev_label=None, prev_motion=None):
    # Stampa solo se qualcosa è cambiato (o ogni 20 campioni comunque)
    changed = (orient_label != prev_label) or (motion_label != prev_motion)
    if not changed and sample_num % 20 != 0:
        return orient_label, motion_label

    sep = c("─" * 52, "grey")
    print(sep)
    print(c(f"  Campione #{sample_num}  |  ts={ts} ms", "grey"))
    print(f"  {orient_emoji}  {c(orient_label, 'cyan')}")
    print(f"  {motion_emoji}  {c(motion_label, 'green' if 'Fermo' in motion_label else 'yellow' if 'movimento' in motion_label else 'red')}")
    print(f"  {mag_emoji}  {c(mag_label, 'cyan')}")
    print(f"  {c('Var accel:', 'grey')} {accel_var:.4f}")

    if orient_label != prev_label and prev_label is not None:
        print(f"  {c('⚠️  Cambio orientamento!', 'red')}")
    if motion_label != prev_motion and prev_motion is not None:
        print(f"  {c('➡️  Cambio stato moto!', 'yellow')}")

    return orient_label, motion_label


# ─────────────────────────────────────────────
#  MAIN LOOP
# ─────────────────────────────────────────────
def process(filepath, follow=False):
    accel_window = deque(maxlen=WINDOW)
    gyro_window  = deque(maxlen=WINDOW)
    mag_window   = deque(maxlen=WINDOW)   # magnitudini magnetometro
    mag_ts_win   = deque(maxlen=WINDOW)   # timestamp corrispondenti
    mag_delta_win = deque(maxlen=WINDOW)  # delta µT/s

    prev_orient = None
    prev_motion = None
    sample_num  = 0

    print(c("\n  IMU Interpreter — avviato\n", "bold"))

    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        while True:
            line = f.readline()
            if not line:
                if follow:
                    time.sleep(0.05)
                    continue
                else:
                    break

            parsed = parse_line(line)
            if parsed is None:
                continue

            ts, accel, gyro, mag = parsed
            sample_num += 1

            ax, ay, az = accel
            gx, gy, gz = gyro
            mx, my, mz = mag

            accel_window.append(accel)
            gyro_window.append(gyro)

            mag_mag = magnitude(mx, my, mz)
            if mag_window:
                prev_mag = mag_window[-1]
                prev_ts  = mag_ts_win[-1]
                dt = (ts - prev_ts) / 1000.0  # ms → s
                if dt > 0:
                    delta = abs(mag_mag - prev_mag) / dt
                    mag_delta_win.append(delta)
            mag_window.append(mag_mag)
            mag_ts_win.append(ts)

            # Orientamento
            orient_label, orient_emoji = interpret_orientation(ax, ay, az)

            # Moto (solo se finestra piena)
            if len(accel_window) >= WINDOW // 2:
                motion_label, motion_emoji, a_var = interpret_motion(accel_window, gyro_window)
            else:
                motion_label, motion_emoji, a_var = "Raccolta dati...", "⏳", 0.0

            # Magnetometro
            mag_label, mag_emoji = interpret_mag_speed(list(mag_delta_win))

            # Pitch / Roll
            pitch, roll = pitch_roll(ax, ay, az)

            prev_orient, prev_motion = print_state(
                sample_num, ts,
                orient_label, orient_emoji,
                motion_label, motion_emoji,
                mag_label, mag_emoji,
                pitch, roll, a_var,
                prev_orient, prev_motion
            )

    print(c(f"\n  Fine elaborazione — {sample_num} campioni letti.\n", "bold"))


def main():
    parser = argparse.ArgumentParser(description="IMU Sensor Interpreter")
    parser.add_argument("file", help="File di log Flutter")
    parser.add_argument("--follow", "-f", action="store_true",
                        help="Segui il file in tempo reale (come tail -f)")
    args = parser.parse_args()

    try:
        process(args.file, follow=args.follow)
    except FileNotFoundError:
        print(f"Errore: file '{args.file}' non trovato.", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nInterrotto.")


if __name__ == "__main__":
    main()