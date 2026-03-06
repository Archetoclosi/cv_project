"""
Hand Analyzer
==============
Rileva per ogni mano inquadrata dalla webcam:
  1. ORIENTAMENTO  → il palmo è rivolto verso la camera o dall'altra parte?
  2. PRESA         → la mano sta stringendo qualcosa?

Output visivo:
  - Riquadro verde  = palmo verso camera + presa rilevata  (telefono puntato verso webcam)
  - Riquadro giallo = solo uno dei due criteri soddisfatto
  - Riquadro rosso  = nessun criterio

Dipendenze:
    pip install mediapipe opencv-python numpy

Uso:
    python hand_analyzer.py
    python hand_analyzer.py --source video.mp4
    python hand_analyzer.py --debug     # mostra valori numerici in tempo reale
"""

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.vision import HandLandmarkerOptions, RunningMode
import numpy as np
import argparse
import urllib.request
from pathlib import Path


# ─────────────────────────────────────────────
# Modello
# ─────────────────────────────────────────────

MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
MODEL_PATH = Path("hand_landmarker.task")


def download_model():
    if not MODEL_PATH.exists():
        print("[INFO] Download modello Hand Landmarker (~25MB)...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print(f"[INFO] Modello salvato in {MODEL_PATH}")
    else:
        print(f"[INFO] Modello già presente: {MODEL_PATH}")


# ─────────────────────────────────────────────
# Indici keypoint MediaPipe Hands
# ─────────────────────────────────────────────

WRIST      = 0
THUMB_CMC  = 1;  THUMB_TIP  = 4
INDEX_MCP  = 5;  INDEX_PIP  = 6;  INDEX_TIP  = 8
MIDDLE_MCP = 9;  MIDDLE_PIP = 10; MIDDLE_TIP = 12
RING_MCP   = 13; RING_PIP   = 14; RING_TIP   = 16
PINKY_MCP  = 17; PINKY_PIP  = 18; PINKY_TIP  = 20


# ─────────────────────────────────────────────
# Analisi orientamento palmo
# ─────────────────────────────────────────────

def compute_palm_normal(landmarks) -> np.ndarray:
    """
    Calcola la normale del piano del palmo usando tre punti:
    polso, nocca indice, nocca mignolo.

    La normale positiva (z > 0 nello spazio della camera) indica
    che il palmo è rivolto verso la camera.
    """
    wrist  = np.array([landmarks[WRIST].x,      landmarks[WRIST].y,      landmarks[WRIST].z])
    index  = np.array([landmarks[INDEX_MCP].x,  landmarks[INDEX_MCP].y,  landmarks[INDEX_MCP].z])
    pinky  = np.array([landmarks[PINKY_MCP].x,  landmarks[PINKY_MCP].y,  landmarks[PINKY_MCP].z])

    v1 = index - wrist
    v2 = pinky - wrist

    normal = np.cross(v1, v2)
    norm   = np.linalg.norm(normal)
    if norm < 1e-6:
        return np.zeros(3)
    return normal / norm


def is_palm_facing_camera(landmarks, handedness: str) -> tuple[bool, float]:
    """
    Determina se il palmo è rivolto verso la camera.

    MediaPipe restituisce le coordinate con z negativo verso la camera,
    quindi il segno della normale Z va invertito per la mano destra
    a causa del sistema di riferimento speculare.

    Returns:
        (facing: bool, confidence: float 0-1)
    """
    normal = compute_palm_normal(landmarks)
    z      = normal[2]

    # Per la mano destra il sistema di coordinate è speculare
    if handedness == "Right":
        z = -z

    # confidence: quanto è "frontale" il palmo (1.0 = perfettamente frontale)
    confidence = float(np.clip(z, 0.0, 1.0))
    facing     = z > 0.15   # soglia tollerante per uso reale

    return facing, confidence


# ─────────────────────────────────────────────
# Analisi presa
# ─────────────────────────────────────────────

def finger_bend_ratio(landmarks, mcp_idx: int, pip_idx: int, tip_idx: int) -> float:
    """
    Calcola quanto è piegato un dito (0.0 = disteso, 1.0 = completamente piegato).

    Metodo: confronta la distanza TIP-MCP con la distanza TIP-WRIST.
    Quando il dito è piegato, il tip si avvicina al polso rispetto alla nocca.
    """
    wrist = np.array([landmarks[WRIST].x, landmarks[WRIST].y])
    mcp   = np.array([landmarks[mcp_idx].x, landmarks[mcp_idx].y])
    tip   = np.array([landmarks[tip_idx].x, landmarks[tip_idx].y])

    dist_tip_wrist = np.linalg.norm(tip - wrist)
    dist_mcp_wrist = np.linalg.norm(mcp - wrist)

    if dist_mcp_wrist < 1e-6:
        return 0.0

    # Ratio < 1 → tip più vicino al polso del mcp → dito piegato
    ratio = dist_tip_wrist / dist_mcp_wrist
    # Normalizza: ratio ~1.7 = disteso, ratio ~0.8 = piegato
    bend = float(np.clip((1.7 - ratio) / 0.9, 0.0, 1.0))
    return bend


def analyze_grip(landmarks) -> tuple[bool, float, dict]:
    """
    Determina se la mano sta stringendo qualcosa.

    Strategia: almeno 3 dita su 4 (escluso pollice) devono essere
    piegate oltre la soglia. Il pollice viene analizzato separatamente
    come "dito di chiusura".

    Returns:
        (gripping: bool, confidence: float, details: dict con bend per dito)
    """
    fingers = {
        "indice":  finger_bend_ratio(landmarks, INDEX_MCP,  INDEX_PIP,  INDEX_TIP),
        "medio":   finger_bend_ratio(landmarks, MIDDLE_MCP, MIDDLE_PIP, MIDDLE_TIP),
        "anulare": finger_bend_ratio(landmarks, RING_MCP,   RING_PIP,   RING_TIP),
        "mignolo": finger_bend_ratio(landmarks, PINKY_MCP,  PINKY_PIP,  PINKY_TIP),
    }

    # Pollice: analisi semplificata (si muove su asse diverso)
    thumb_tip   = np.array([landmarks[THUMB_TIP].x,  landmarks[THUMB_TIP].y])
    index_mcp   = np.array([landmarks[INDEX_MCP].x,  landmarks[INDEX_MCP].y])
    pinky_mcp   = np.array([landmarks[PINKY_MCP].x,  landmarks[PINKY_MCP].y])
    palm_width  = np.linalg.norm(index_mcp - pinky_mcp)
    thumb_dist  = np.linalg.norm(thumb_tip - index_mcp)
    thumb_bent  = float(np.clip(1.0 - (thumb_dist / (palm_width + 1e-6)), 0.0, 1.0))
    fingers["pollice"] = thumb_bent

    BEND_THRESHOLD = 0.28   # soglia rilassata: rileva presa larga (oggetto in mano)
    bent_count     = sum(1 for f, v in fingers.items() if f != "pollice" and v > BEND_THRESHOLD)
    avg_bend       = float(np.mean(list(fingers.values())))

    gripping   = bent_count >= 3
    confidence = float(np.clip(avg_bend, 0.0, 1.0))

    return gripping, confidence, fingers


# ─────────────────────────────────────────────
# Disegno
# ─────────────────────────────────────────────

# Connessioni scheletro mano
HAND_CONNECTIONS = [
    (0,1),(1,2),(2,3),(3,4),          # pollice
    (0,5),(5,6),(6,7),(7,8),          # indice
    (0,9),(9,10),(10,11),(11,12),     # medio
    (0,13),(13,14),(14,15),(15,16),   # anulare
    (0,17),(17,18),(18,19),(19,20),   # mignolo
    (5,9),(9,13),(13,17),             # dorso
]

# Colori stato
COLOR_OK      = (0,   220, 80)    # verde  → palmo verso cam + tiene qualcosa
COLOR_HOLDING = (220, 120, 0)     # blu    → tiene qualcosa (palmo non verso cam)
COLOR_PARTIAL = (0,   200, 255)   # giallo → palmo verso cam, mano aperta
COLOR_NO      = (50,  50,  220)   # rosso  → nessuno
COLOR_BONE    = (200, 200, 200)
COLOR_JOINT   = (255, 255, 255)


def state_color(facing: bool, gripping: bool) -> tuple:
    if facing and gripping:
        return COLOR_OK       # verde  → palmo verso cam + tiene qualcosa
    if gripping:
        return COLOR_HOLDING  # blu    → tiene qualcosa ma palmo non verso cam
    if facing:
        return COLOR_PARTIAL  # giallo → palmo verso cam, mano aperta
    return COLOR_NO           # rosso  → nessuno


def draw_hand(frame: np.ndarray, landmarks, w: int, h: int, color: tuple):
    """Disegna scheletro mano con il colore dello stato."""
    pts = [(int(lm.x * w), int(lm.y * h)) for lm in landmarks]

    for (a, b) in HAND_CONNECTIONS:
        cv2.line(frame, pts[a], pts[b], COLOR_BONE, 2, cv2.LINE_AA)

    for i, pt in enumerate(pts):
        cv2.circle(frame, pt, 6, color, -1)
        cv2.circle(frame, pt, 6, COLOR_JOINT, 1)


def draw_hand_info(frame: np.ndarray, landmarks, w: int, h: int,
                   handedness: str, facing: bool, face_conf: float,
                   gripping: bool, grip_conf: float,
                   finger_details: dict, debug: bool):
    """Disegna il riquadro informativo sopra la mano."""

    # Bounding box della mano
    xs = [int(lm.x * w) for lm in landmarks]
    ys = [int(lm.y * h) for lm in landmarks]
    x1, y1 = max(min(xs) - 20, 0), max(min(ys) - 60, 0)
    x2, y2 = min(max(xs) + 20, w), min(max(ys) + 20, h)

    color = state_color(facing, gripping)

    # Riquadro
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

    # Etichette stato
    face_label  = "PALMO →CAM" if facing   else "DORSO →CAM"
    grip_label  = "TIENE"      if gripping else "APERTA"
    main_label  = f"{handedness.upper()}  |  {face_label}  |  {grip_label}"

    # Sfondo testo
    (tw, th), _ = cv2.getTextSize(main_label, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
    cv2.rectangle(frame, (x1, y1 - th - 10), (x1 + tw + 8, y1), (0, 0, 0), -1)
    cv2.putText(frame, main_label, (x1 + 4, y1 - 5),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 1, cv2.LINE_AA)

    # Modalità debug: barre di piegatura dita
    if debug:
        bar_x = x2 + 8
        bar_y = y1
        for fname, fval in finger_details.items():
            bar_len = int(fval * 60)
            bcolor  = (0, 200, 80) if fval > 0.45 else (80, 80, 200)
            cv2.rectangle(frame, (bar_x, bar_y), (bar_x + bar_len, bar_y + 12), bcolor, -1)
            cv2.putText(frame, f"{fname[:3]} {fval:.2f}", (bar_x + 65, bar_y + 11),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.38, (220, 220, 220), 1)
            bar_y += 18

        cv2.putText(frame, f"palm_z conf: {face_conf:.2f}", (bar_x, bar_y + 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.38, (180, 180, 180), 1)


def draw_legend(frame: np.ndarray):
    """Legenda fissa in basso a sinistra."""
    h, w = frame.shape[:2]
    items = [
        (COLOR_OK,      "Palmo verso cam + tiene qualcosa"),
        (COLOR_HOLDING, "Tiene qualcosa (palmo non verso cam)"),
        (COLOR_PARTIAL, "Palmo verso cam, mano aperta"),
        (COLOR_NO,      "Nessun criterio"),
    ]
    y = h - 10
    for color, label in reversed(items):
        cv2.circle(frame, (18, y - 4), 7, color, -1)
        cv2.putText(frame, label, (30, y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.48, (220, 220, 220), 1, cv2.LINE_AA)
        y -= 22


def draw_fps(frame: np.ndarray, fps: float):
    cv2.putText(frame, f"FPS {fps:.1f}", (10, 24),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (180, 180, 180), 2, cv2.LINE_AA)


# ─────────────────────────────────────────────
# Detector principale
# ─────────────────────────────────────────────

class HandAnalyzer:
    def __init__(self, debug: bool = False):
        self.debug = debug
        download_model()

        options = HandLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=str(MODEL_PATH)),
            running_mode=RunningMode.VIDEO,
            num_hands=2,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        self.landmarker = mp_vision.HandLandmarker.create_from_options(options)

        self._frame_n = 0
        self._fps     = 0.0
        self._tick    = cv2.getTickCount()

    def process(self, frame: np.ndarray, timestamp_ms: int) -> np.ndarray:
        h, w = frame.shape[:2]
        rgb     = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img  = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        results = self.landmarker.detect_for_video(mp_img, timestamp_ms)

        for i, hand_landmarks in enumerate(results.hand_landmarks):
            handedness = results.handedness[i][0].display_name  # "Left" / "Right"

            facing,   face_conf              = is_palm_facing_camera(hand_landmarks, handedness)
            gripping, grip_conf, finger_det  = analyze_grip(hand_landmarks)

            color = state_color(facing, gripping)
            draw_hand(frame, hand_landmarks, w, h, color)
            draw_hand_info(frame, hand_landmarks, w, h,
                           handedness, facing, face_conf,
                           gripping, grip_conf, finger_det, self.debug)

        draw_legend(frame)

        # FPS
        self._frame_n += 1
        if self._frame_n % 15 == 0:
            now        = cv2.getTickCount()
            self._fps  = 15 / ((now - self._tick) / cv2.getTickFrequency())
            self._tick = now
        draw_fps(frame, self._fps)

        return frame

    def close(self):
        self.landmarker.close()


# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(description="Hand Analyzer — orientamento e presa")
    p.add_argument("--source", default="0",
                   help="0/1 per webcam, oppure path a un video")
    p.add_argument("--debug",  action="store_true",
                   help="Mostra barre di piegatura dita e valori numerici")
    return p.parse_args()


def main():
    args    = parse_args()
    source  = int(args.source) if args.source.isdigit() else args.source
    analyzer = HandAnalyzer(debug=args.debug)

    cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        print(f"[ERRORE] Impossibile aprire la sorgente: {args.source}")
        return

    print("[INFO] Avviato. Premi Q per uscire.")
    print("[INFO] Verde = palmo verso cam + tiene | Blu = tiene (palmo opposto) | Giallo = palmo verso cam | Rosso = nessuno")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        timestamp_ms = int(cap.get(cv2.CAP_PROP_POS_MSEC))
        out = analyzer.process(frame, timestamp_ms)

        cv2.imshow("Hand Analyzer", out)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()
    analyzer.close()


if __name__ == "__main__":
    main()