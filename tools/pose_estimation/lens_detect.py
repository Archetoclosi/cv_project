"""
Lens Detector
==============
Rileva se l'utente sta puntando la fotocamera di un telefono verso la webcam.

Combina 5 segnali per evitare falsi positivi:
  1. Mano in "presa" (dita semi-piegate, tiene un oggetto)
  2. Dorso della mano verso la camera (palmo lontano dalla webcam)
  3. Cerchio scuro nell'area delle dita (HoughCircles)
  4. Alone chiaro attorno al cerchio (anello metallico della lente)
  5. Stabilità temporale (il cerchio persiste per N frame)

Output visivo:
  ● Cerchio CIANO    = lente rilevata con alta confidenza
  ● Cerchio GIALLO   = candidato lente (non ancora stabile)
  ● Overlay Verde    = telefono puntato verso webcam (tutti i criteri OK)
  ● Overlay Rosso    = nessun rilevamento

Dipendenze:
    pip install mediapipe opencv-python numpy

Uso:
    python lens_detector.py
    python lens_detector.py --source video.mp4
    python lens_detector.py --debug      # mostra tutti i cerchi candidati e score
"""

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.vision import HandLandmarkerOptions, RunningMode
import numpy as np
import argparse
import urllib.request
from collections import deque
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
THUMB_TIP  = 4
INDEX_MCP  = 5;  INDEX_PIP  = 6;  INDEX_TIP  = 8
MIDDLE_MCP = 9;  MIDDLE_PIP = 10; MIDDLE_TIP = 12
RING_MCP   = 13; RING_PIP   = 14; RING_TIP   = 16
PINKY_MCP  = 17; PINKY_PIP  = 18; PINKY_TIP  = 20


# ─────────────────────────────────────────────
# Analisi mano (da hand_analyzer.py)
# ─────────────────────────────────────────────

def compute_palm_normal(landmarks) -> np.ndarray:
    wrist = np.array([landmarks[WRIST].x,     landmarks[WRIST].y,     landmarks[WRIST].z])
    index = np.array([landmarks[INDEX_MCP].x, landmarks[INDEX_MCP].y, landmarks[INDEX_MCP].z])
    pinky = np.array([landmarks[PINKY_MCP].x, landmarks[PINKY_MCP].y, landmarks[PINKY_MCP].z])
    v1     = index - wrist
    v2     = pinky - wrist
    normal = np.cross(v1, v2)
    norm   = np.linalg.norm(normal)
    return normal / norm if norm > 1e-6 else np.zeros(3)


def is_palm_facing_camera(landmarks, handedness: str) -> tuple[bool, float]:
    normal = compute_palm_normal(landmarks)
    z      = normal[2]
    if handedness == "Right":
        z = -z
    return z > 0.15, float(np.clip(z, 0.0, 1.0))


def finger_bend_ratio(landmarks, mcp_idx, pip_idx, tip_idx) -> float:
    wrist          = np.array([landmarks[WRIST].x,    landmarks[WRIST].y])
    mcp            = np.array([landmarks[mcp_idx].x,  landmarks[mcp_idx].y])
    tip            = np.array([landmarks[tip_idx].x,  landmarks[tip_idx].y])
    dist_tip_wrist = np.linalg.norm(tip - wrist)
    dist_mcp_wrist = np.linalg.norm(mcp - wrist)
    if dist_mcp_wrist < 1e-6:
        return 0.0
    ratio = dist_tip_wrist / dist_mcp_wrist
    return float(np.clip((1.7 - ratio) / 0.9, 0.0, 1.0))


def analyze_grip(landmarks) -> tuple[bool, float]:
    bends = [
        finger_bend_ratio(landmarks, INDEX_MCP,  INDEX_PIP,  INDEX_TIP),
        finger_bend_ratio(landmarks, MIDDLE_MCP, MIDDLE_PIP, MIDDLE_TIP),
        finger_bend_ratio(landmarks, RING_MCP,   RING_PIP,   RING_TIP),
        finger_bend_ratio(landmarks, PINKY_MCP,  PINKY_PIP,  PINKY_TIP),
    ]
    BEND_THRESHOLD = 0.28
    bent_count     = sum(1 for v in bends if v > BEND_THRESHOLD)
    return bent_count >= 3, float(np.mean(bends))


def hand_bbox(landmarks, w: int, h: int, padding: int = 20) -> tuple[int,int,int,int]:
    """Bounding box della mano in pixel."""
    xs = [int(lm.x * w) for lm in landmarks]
    ys = [int(lm.y * h) for lm in landmarks]
    return (max(min(xs)-padding, 0), max(min(ys)-padding, 0),
            min(max(xs)+padding, w), min(max(ys)+padding, h))


def fingertip_zone(landmarks, w: int, h: int) -> tuple[int,int,int,int]:
    """
    Zona delle punte delle dita: è qui che appare la lente del telefono
    quando la mano lo tiene con il dorso verso la camera.
    Esclude il polso per ridurre l'area di ricerca.
    """
    tips = [INDEX_TIP, MIDDLE_TIP, RING_TIP, PINKY_TIP, THUMB_TIP,
            INDEX_MCP, MIDDLE_MCP, RING_MCP, PINKY_MCP]
    xs = [int(landmarks[i].x * w) for i in tips]
    ys = [int(landmarks[i].y * h) for i in tips]
    pad = 30
    return (max(min(xs)-pad, 0), max(min(ys)-pad, 0),
            min(max(xs)+pad, w), min(max(ys)+pad, h))


# ─────────────────────────────────────────────
# Rilevamento lente
# ─────────────────────────────────────────────

def score_circle_as_lens(frame_gray: np.ndarray, frame_bgr: np.ndarray,
                          cx: int, cy: int, r: int,
                          zone: tuple[int,int,int,int]) -> float:
    """
    Calcola uno score 0.0-1.0 che indica quanto un cerchio rilevato
    somiglia alla lente di una fotocamera.

    Criteri:
      A. Scurezza interna   → l'interno è significativamente più scuro della zona
      B. Alone chiaro       → i pixel appena fuori dal cerchio sono più chiari dell'interno
      C. Uniformità interna → bassa varianza = superficie uniforme (vetro/plastica)
      D. Posizione          → il cerchio è nella zona delle dita (non nel palmo)
      E. Dimensione         → proporzionale alla mano (non troppo grande/piccolo)
    """
    h, w = frame_gray.shape
    score = 0.0

    # ── A. Scurezza interna ──────────────────────────
    mask_inner = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(mask_inner, (cx, cy), max(r - 2, 1), 255, -1)
    inner_pixels = frame_gray[mask_inner > 0]
    if len(inner_pixels) == 0:
        return 0.0
    inner_mean = float(np.mean(inner_pixels))

    # media della zona della mano come riferimento
    zx1, zy1, zx2, zy2 = zone
    zone_pixels = frame_gray[zy1:zy2, zx1:zx2]
    zone_mean   = float(np.mean(zone_pixels)) if zone_pixels.size > 0 else 128.0

    darkness_ratio = (zone_mean - inner_mean) / (zone_mean + 1e-6)
    score += float(np.clip(darkness_ratio * 2.5, 0.0, 0.35))   # max 0.35

    # ── B. Alone chiaro (anello metallico) ───────────
    mask_ring = np.zeros((h, w), dtype=np.uint8)
    cv2.circle(mask_ring, (cx, cy), r + 4, 255, -1)
    cv2.circle(mask_ring, (cx, cy), r,     0,   -1)
    ring_pixels = frame_gray[mask_ring > 0]
    if len(ring_pixels) > 0:
        ring_mean    = float(np.mean(ring_pixels))
        halo_ratio   = (ring_mean - inner_mean) / (ring_mean + 1e-6)
        score       += float(np.clip(halo_ratio * 1.5, 0.0, 0.25))  # max 0.25

    # ── C. Uniformità interna ─────────────────────────
    inner_std  = float(np.std(inner_pixels))
    uniformity = float(np.clip(1.0 - inner_std / 60.0, 0.0, 1.0))
    score     += uniformity * 0.20                                   # max 0.20

    # ── D. Posizione nella zona dita ──────────────────
    zx1, zy1, zx2, zy2 = zone
    in_zone = zx1 <= cx <= zx2 and zy1 <= cy <= zy2
    score  += 0.10 if in_zone else 0.0                              # max 0.10

    # ── E. Dimensione ragionevole ─────────────────────
    zone_w  = max(zx2 - zx1, 1)
    r_ratio = r / zone_w
    # lente tipica: 3-15% della larghezza della mano
    if 0.03 <= r_ratio <= 0.18:
        score += 0.10                                                # max 0.10

    return float(np.clip(score, 0.0, 1.0))


def find_lens_candidates(frame_bgr: np.ndarray, zone: tuple[int,int,int,int],
                          debug: bool = False) -> list[tuple[int,int,int,float]]:
    """
    Cerca cerchi candidati lente nell'area della zona dita.

    Returns:
        Lista di (cx, cy, r, score) ordinata per score decrescente.
    """
    zx1, zy1, zx2, zy2 = zone
    crop    = frame_bgr[zy1:zy2, zx1:zx2]
    if crop.size == 0:
        return []

    gray    = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (7, 7), 1.5)

    # HoughCircles: cerca cerchi di dimensione compatibile con una lente
    zone_w  = zx2 - zx1
    min_r   = max(int(zone_w * 0.03), 5)
    max_r   = max(int(zone_w * 0.20), min_r + 5)

    circles = cv2.HoughCircles(
        blurred,
        cv2.HOUGH_GRADIENT,
        dp=1.2,
        minDist=min_r * 2,
        param1=60,    # soglia Canny alta
        param2=22,    # soglia accumulatore (più basso = più candidati)
        minRadius=min_r,
        maxRadius=max_r,
    )

    candidates = []
    if circles is not None:
        circles = np.round(circles[0]).astype(int)
        h_full, w_full = frame_bgr.shape[:2]
        gray_full      = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)

        for (cx_crop, cy_crop, r) in circles:
            cx = cx_crop + zx1
            cy = cy_crop + zy1
            # assicura che il cerchio sia dentro il frame
            if cx - r < 0 or cy - r < 0 or cx + r >= w_full or cy + r >= h_full:
                continue
            s = score_circle_as_lens(gray_full, frame_bgr, cx, cy, r, zone)
            candidates.append((cx, cy, r, s))

    candidates.sort(key=lambda x: x[3], reverse=True)
    return candidates


# ─────────────────────────────────────────────
# Tracker temporale
# ─────────────────────────────────────────────

class LensTracker:
    """
    Tiene traccia della posizione della lente negli ultimi N frame.
    Un rilevamento è considerato stabile solo se persiste abbastanza a lungo
    e non salta troppo tra un frame e l'altro.
    """

    HISTORY      = 10     # frame da tenere in memoria
    MIN_HITS     = 6      # rilevamenti minimi su HISTORY per considerarla stabile
    MAX_JUMP_PX  = 40     # spostamento massimo accettabile tra frame (pixel)
    MIN_SCORE    = 0.38   # score minimo per accettare un candidato

    def __init__(self):
        self._history: deque = deque(maxlen=self.HISTORY)  # (cx, cy, r, score) | None
        self.stable_lens: tuple[int,int,int] | None = None  # (cx, cy, r)

    def update(self, candidates: list[tuple[int,int,int,float]]):
        """Aggiorna lo storico con il miglior candidato del frame corrente."""
        best = None
        if candidates:
            top = candidates[0]
            if top[3] >= self.MIN_SCORE:
                # controlla che non salti troppo rispetto all'ultimo rilevamento
                last = next((x for x in reversed(self._history) if x is not None), None)
                if last is None:
                    best = top
                else:
                    dist = np.hypot(top[0] - last[0], top[1] - last[1])
                    if dist <= self.MAX_JUMP_PX:
                        best = top

        self._history.append(best)

        # calcola stabilità
        hits = sum(1 for x in self._history if x is not None)
        if hits >= self.MIN_HITS:
            # posizione media degli ultimi rilevamenti validi
            valids = [x for x in self._history if x is not None]
            cx = int(np.mean([v[0] for v in valids]))
            cy = int(np.mean([v[1] for v in valids]))
            r  = int(np.mean([v[2] for v in valids]))
            self.stable_lens = (cx, cy, r)
        else:
            self.stable_lens = None

    @property
    def hit_ratio(self) -> float:
        hits = sum(1 for x in self._history if x is not None)
        return hits / max(len(self._history), 1)


# ─────────────────────────────────────────────
# Disegno
# ─────────────────────────────────────────────

HAND_CONNECTIONS = [
    (0,1),(1,2),(2,3),(3,4),
    (0,5),(5,6),(6,7),(7,8),
    (0,9),(9,10),(10,11),(11,12),
    (0,13),(13,14),(14,15),(15,16),
    (0,17),(17,18),(18,19),(19,20),
    (5,9),(9,13),(13,17),
]

COLOR_LENS_STABLE    = (255, 220,  0)   # ciano   → lente confermata
COLOR_LENS_CANDIDATE = (0,   200, 255)  # giallo  → candidato instabile
COLOR_HAND_OK        = (0,   220, 80)   # verde   → telefono puntato verso cam
COLOR_HAND_HOLD      = (220, 120,  0)   # blu     → tiene ma dorso non verso cam
COLOR_HAND_NONE      = (60,   60, 200)  # rosso   → nessun rilevamento
COLOR_BONE           = (180, 180, 180)
COLOR_JOINT          = (255, 255, 255)


def draw_hand_skeleton(frame, landmarks, w, h, color):
    pts = [(int(lm.x * w), int(lm.y * h)) for lm in landmarks]
    for (a, b) in HAND_CONNECTIONS:
        cv2.line(frame, pts[a], pts[b], COLOR_BONE, 2, cv2.LINE_AA)
    for pt in pts:
        cv2.circle(frame, pt, 5, color, -1)
        cv2.circle(frame, pt, 5, COLOR_JOINT, 1)


def draw_lens(frame, tracker: LensTracker, candidates: list, debug: bool):
    # debug: mostra tutti i candidati in grigio con score
    if debug:
        for (cx, cy, r, s) in candidates:
            cv2.circle(frame, (cx, cy), r, (100, 100, 100), 1, cv2.LINE_AA)
            cv2.putText(frame, f"{s:.2f}", (cx - 12, cy - r - 4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.35, (150, 150, 150), 1)

    # candidato instabile (primo della lista sopra soglia)
    if candidates and candidates[0][3] >= LensTracker.MIN_SCORE:
        cx, cy, r, _ = candidates[0]
        cv2.circle(frame, (cx, cy), r + 2, COLOR_LENS_CANDIDATE, 1, cv2.LINE_AA)

    # lente stabile confermata
    if tracker.stable_lens:
        cx, cy, r = tracker.stable_lens
        cv2.circle(frame, (cx, cy), r + 4, COLOR_LENS_STABLE, 2, cv2.LINE_AA)
        cv2.circle(frame, (cx, cy), 3,     COLOR_LENS_STABLE, -1)

        # etichetta
        label = "LENS"
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2)
        lx, ly = cx - tw // 2, cy - r - 10
        cv2.rectangle(frame, (lx - 4, ly - th - 4), (lx + tw + 4, ly + 4), (0,0,0), -1)
        cv2.putText(frame, label, (lx, ly),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, COLOR_LENS_STABLE, 2, cv2.LINE_AA)

        # hit ratio debug
        if debug:
            cv2.putText(frame, f"stab:{tracker.hit_ratio:.0%}", (cx - 20, cy + r + 16),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.38, COLOR_LENS_STABLE, 1)


def draw_phone_overlay(frame, detected: bool, lens_stable: bool):
    """Overlay semitrasparente verde/rosso + messaggio principale."""
    h, w = frame.shape[:2]
    overlay = frame.copy()

    if detected and lens_stable:
        color   = (0, 180, 60)
        message = "TELEFONO VERSO WEBCAM"
    else:
        color   = (40, 40, 180)
        message = "Nessun rilevamento"

    cv2.rectangle(overlay, (0, 0), (w, 44), color, -1)
    cv2.addWeighted(overlay, 0.35, frame, 0.65, 0, frame)

    (tw, _), _ = cv2.getTextSize(message, cv2.FONT_HERSHEY_SIMPLEX, 0.75, 2)
    cv2.putText(frame, message, (w // 2 - tw // 2, 30),
                cv2.FONT_HERSHEY_SIMPLEX, 0.75, (255, 255, 255), 2, cv2.LINE_AA)


def draw_legend(frame):
    h, w = frame.shape[:2]
    items = [
        (COLOR_LENS_STABLE,    "Lente confermata (stabile)"),
        (COLOR_LENS_CANDIDATE, "Candidato lente (instabile)"),
        (COLOR_HAND_OK,        "Dorso mano + tiene + lente → telefono verso cam"),
        (COLOR_HAND_HOLD,      "Tiene ma dorso non verso cam"),
    ]
    y = h - 10
    for color, label in reversed(items):
        cv2.circle(frame, (18, y - 4), 7, color, -1)
        cv2.putText(frame, label, (32, y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.42, (210, 210, 210), 1, cv2.LINE_AA)
        y -= 20


def draw_fps(frame, fps):
    cv2.putText(frame, f"FPS {fps:.1f}", (10, 70),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (180, 180, 180), 1, cv2.LINE_AA)


# ─────────────────────────────────────────────
# Detector principale
# ─────────────────────────────────────────────

class LensDetector:
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
        self.trackers: dict[int, LensTracker] = {}  # un tracker per mano

        self._frame_n = 0
        self._fps     = 0.0
        self._tick    = cv2.getTickCount()

    def process(self, frame: np.ndarray, timestamp_ms: int) -> tuple[np.ndarray, bool]:
        """
        Returns:
            (frame annotato, phone_detected: bool)
        """
        h, w   = frame.shape[:2]
        rgb    = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_img = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        results = self.landmarker.detect_for_video(mp_img, timestamp_ms)

        phone_detected = False
        active_ids     = set()

        for i, hand_landmarks in enumerate(results.hand_landmarks):
            handedness          = results.handedness[i][0].display_name
            facing, _           = is_palm_facing_camera(hand_landmarks, handedness)
            gripping, _         = analyze_grip(hand_landmarks)

            # dorso verso cam = NON facing
            dorso_verso_cam = not facing

            # zona di ricerca lente
            zone       = fingertip_zone(hand_landmarks, w, h)
            candidates = find_lens_candidates(frame, zone, self.debug)

            # tracker per questa mano
            if i not in self.trackers:
                self.trackers[i] = LensTracker()
            tracker = self.trackers[i]

            # aggiorna tracker solo se dorso verso cam (ha senso cercare la lente)
            if dorso_verso_cam and gripping:
                tracker.update(candidates)
            else:
                tracker.update([])  # reset graduale

            active_ids.add(i)

            # stato finale per questa mano
            lens_ok = tracker.stable_lens is not None
            hand_detected = dorso_verso_cam and gripping and lens_ok

            if hand_detected:
                phone_detected = True

            # disegno
            hand_color = COLOR_HAND_OK if hand_detected else (
                         COLOR_HAND_HOLD if gripping else COLOR_HAND_NONE)
            draw_hand_skeleton(frame, hand_landmarks, w, h, hand_color)
            draw_lens(frame, tracker, candidates, self.debug)

            # info mano
            bbox = hand_bbox(hand_landmarks, w, h)
            x1, y1 = bbox[0], bbox[1]
            labels = []
            labels.append("DORSO→CAM" if dorso_verso_cam else "PALMO→CAM")
            labels.append("TIENE" if gripping else "APERTA")
            labels.append("LENTE ✓" if lens_ok else "lente?")
            info = f"{handedness}  {'  '.join(labels)}"
            (tw, th), _ = cv2.getTextSize(info, cv2.FONT_HERSHEY_SIMPLEX, 0.48, 1)
            cv2.rectangle(frame, (x1, y1 - th - 10), (x1 + tw + 6, y1), (0,0,0), -1)
            cv2.putText(frame, info, (x1 + 3, y1 - 4),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.48, hand_color, 1, cv2.LINE_AA)

        # pulisci tracker mani non più visibili
        for old_id in list(self.trackers.keys()):
            if old_id not in active_ids:
                del self.trackers[old_id]

        draw_phone_overlay(frame, phone_detected, phone_detected)
        draw_legend(frame)

        # FPS
        self._frame_n += 1
        if self._frame_n % 15 == 0:
            now       = cv2.getTickCount()
            self._fps = 15 / ((now - self._tick) / cv2.getTickFrequency())
            self._tick = now
        draw_fps(frame, self._fps)

        return frame, phone_detected

    def close(self):
        self.landmarker.close()


# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(description="Lens Detector — rileva fotocamera telefono verso webcam")
    p.add_argument("--source", default="0",
                   help="0/1 per webcam, oppure path a un video")
    p.add_argument("--debug",  action="store_true",
                   help="Mostra cerchi candidati, score e stabilità")
    return p.parse_args()


def main():
    args     = parse_args()
    source   = int(args.source) if args.source.isdigit() else args.source
    detector = LensDetector(debug=args.debug)

    cap = cv2.VideoCapture(source)
    if not cap.isOpened():
        print(f"[ERRORE] Impossibile aprire la sorgente: {args.source}")
        return

    print("[INFO] Avviato. Premi Q per uscire.")
    print("[INFO] Punta il retro del telefono verso la webcam tenendolo in mano.")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        timestamp_ms     = int(cap.get(cv2.CAP_PROP_POS_MSEC))
        out, phone_found = detector.process(frame, timestamp_ms)

        cv2.imshow("Lens Detector", out)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()
    detector.close()


if __name__ == "__main__":
    main()