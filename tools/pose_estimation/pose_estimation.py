"""
Pose Estimation con MediaPipe
==============================
Sviluppato per Windows, progettato per essere portato su Flutter.
Compatibile con MediaPipe 0.10+ (nuova Tasks API).

Dipendenze:
    pip install mediapipe opencv-python numpy

Uso:
    python pose_estimation.py                  # webcam
    python pose_estimation.py --source video.mp4
    python pose_estimation.py --source image.jpg
    python pose_estimation.py --source video.mp4 --save output.mp4
"""

import cv2
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.vision import PoseLandmarkerOptions, RunningMode
import numpy as np
import argparse
import json
import sys
import urllib.request
from pathlib import Path


# ─────────────────────────────────────────────
# Configurazione
# ─────────────────────────────────────────────

MODEL_URL  = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task"
MODEL_PATH = Path("pose_landmarker_full.task")


class PoseConfig:
    """
    Parametri del modello MediaPipe Pose (Tasks API 0.10+).

    Nota Flutter: questi stessi parametri si ritrovano nel plugin
    google_mlkit_pose_detection su Android/iOS.
    """
    MIN_DETECTION_CONF = 0.5    # soglia rilevamento iniziale
    MIN_TRACKING_CONF  = 0.5    # soglia tracking continuo
    MIN_PRESENCE_CONF  = 0.5    # soglia presenza
    DRAW_LANDMARKS     = True
    SHOW_FPS           = True
    EXPORT_JSON        = False  # salva keypoints in JSON per ogni frame


# ─────────────────────────────────────────────
# Nomi dei 33 keypoint MediaPipe Pose
# (identici all'enum PoseLandmark in Flutter)
# ─────────────────────────────────────────────

LANDMARK_NAMES = [
    "nose", "left_eye_inner", "left_eye", "left_eye_outer",
    "right_eye_inner", "right_eye", "right_eye_outer",
    "left_ear", "right_ear",
    "mouth_left", "mouth_right",
    "left_shoulder", "right_shoulder",
    "left_elbow", "right_elbow",
    "left_wrist", "right_wrist",
    "left_pinky", "right_pinky",
    "left_index", "right_index",
    "left_thumb", "right_thumb",
    "left_hip", "right_hip",
    "left_knee", "right_knee",
    "left_ankle", "right_ankle",
    "left_heel", "right_heel",
    "left_foot_index", "right_foot_index",
]

# Connessioni scheletro da disegnare
SKELETON_CONNECTIONS = [
    # testa
    ("nose", "left_eye"),
    ("nose", "right_eye"),
    ("left_eye", "left_ear"),
    ("right_eye", "right_ear"),
    # busto
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "right_hip"),
    # braccio sinistro
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    # braccio destro
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    # gamba sinistra
    ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"),
    ("left_ankle", "left_heel"),
    ("left_heel", "left_foot_index"),
    # gamba destra
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
    ("right_ankle", "right_heel"),
    ("right_heel", "right_foot_index"),
]


# ─────────────────────────────────────────────
# Funzioni di utilità
# ─────────────────────────────────────────────

def landmarks_to_dict_new(landmarks, frame_w: int, frame_h: int) -> list[dict]:
    """
    Converte i landmark della nuova Tasks API in lista di dizionari.
    Compatibile con MediaPipe 0.10+
    """
    result = []
    for idx, lm in enumerate(landmarks):
        result.append({
            "id":         idx,
            "name":       LANDMARK_NAMES[idx] if idx < len(LANDMARK_NAMES) else f"lm_{idx}",
            "x":          round(lm.x * frame_w, 2),
            "y":          round(lm.y * frame_h, 2),
            "z":          round(lm.z, 4),
            "visibility": round(lm.visibility if hasattr(lm, "visibility") else 1.0, 3),
        })
    return result


def landmarks_to_dict(landmarks, frame_w: int, frame_h: int) -> list[dict]:
    """
    Converte i landmark MediaPipe in una lista di dizionari con coordinate
    in pixel e score di visibilità.

    Questo formato è pensato per essere serializzato in JSON e inviato
    facilmente a Flutter tramite platform channel o REST.
    """
    result = []
    for idx, lm in enumerate(landmarks.landmark):
        result.append({
            "id":         idx,
            "name":       LANDMARK_NAMES[idx],
            "x":          round(lm.x * frame_w, 2),   # pixel
            "y":          round(lm.y * frame_h, 2),
            "z":          round(lm.z, 4),              # profondità relativa
            "visibility": round(lm.visibility, 3),
        })
    return result


def compute_angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """
    Calcola l'angolo (gradi) nel punto B formato dai segmenti BA e BC.
    Utile per classificare pose: es. angolo gomito, ginocchio, anca.

    Args:
        a, b, c: array [x, y] dei tre punti
    """
    ba = a - b
    bc = c - b
    cos_angle = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-6)
    return float(np.degrees(np.arccos(np.clip(cos_angle, -1.0, 1.0))))


def get_landmark_xy(lm_dict: list[dict], name: str) -> np.ndarray:
    """Restituisce [x, y] del landmark con il nome dato."""
    for lm in lm_dict:
        if lm["name"] == name:
            return np.array([lm["x"], lm["y"]])
    return np.zeros(2)


# ─────────────────────────────────────────────
# Classificazione pose di esempio
# (estendibile con un modello ML custom sopra i keypoint)
# ─────────────────────────────────────────────

def classify_pose(lm_dict: list[dict], frame_h: int) -> str:
    """
    Classificazione rule-based basata sugli angoli delle articolazioni.

    Nota: per un classificatore più robusto, puoi:
      1. Raccogliere landmark da molti video con etichette
      2. Addestrare un semplice classificatore (SVM, MLP) su questi dati
      3. Esportare in TFLite e usare tflite_flutter in Flutter
    """
    try:
        l_shoulder = get_landmark_xy(lm_dict, "left_shoulder")
        l_hip      = get_landmark_xy(lm_dict, "left_hip")
        l_knee     = get_landmark_xy(lm_dict, "left_knee")
        l_ankle    = get_landmark_xy(lm_dict, "left_ankle")
        l_elbow    = get_landmark_xy(lm_dict, "left_elbow")
        l_wrist    = get_landmark_xy(lm_dict, "left_wrist")

        knee_angle  = compute_angle(l_hip, l_knee, l_ankle)
        hip_angle   = compute_angle(l_shoulder, l_hip, l_knee)
        elbow_angle = compute_angle(l_shoulder, l_elbow, l_wrist)

        # Regole semplici di classificazione
        if knee_angle < 100 and hip_angle < 120:
            return "SQUAT"
        elif l_hip[1] > frame_h * 0.7 and knee_angle > 160:
            return "IN PIEDI"
        elif l_hip[1] < frame_h * 0.5 and knee_angle > 140:
            return "SEDUTO"
        elif elbow_angle > 160:
            return "BRACCIA DISTESE"
        else:
            return "POSA RILEVATA"
    except Exception:
        return "—"


# ─────────────────────────────────────────────
# Disegno custom (alternativa a mp.solutions.drawing_utils)
# ─────────────────────────────────────────────

def draw_pose(frame: np.ndarray, lm_dict: list[dict]) -> np.ndarray:
    """Disegna scheletro e keypoint sull'immagine."""
    lm_by_name = {lm["name"]: lm for lm in lm_dict}

    # Connessioni
    for (start_name, end_name) in SKELETON_CONNECTIONS:
        if start_name in lm_by_name and end_name in lm_by_name:
            s = lm_by_name[start_name]
            e = lm_by_name[end_name]
            if s["visibility"] > 0.5 and e["visibility"] > 0.5:
                cv2.line(
                    frame,
                    (int(s["x"]), int(s["y"])),
                    (int(e["x"]), int(e["y"])),
                    (0, 255, 120), 2, cv2.LINE_AA
                )

    # Keypoint
    for lm in lm_dict:
        if lm["visibility"] > 0.5:
            cv2.circle(frame, (int(lm["x"]), int(lm["y"])), 5, (255, 80, 0), -1)
            cv2.circle(frame, (int(lm["x"]), int(lm["y"])), 5, (255, 255, 255), 1)

    return frame


def draw_hud(frame: np.ndarray, fps: float, pose_label: str) -> np.ndarray:
    """Disegna FPS e classificazione pose sull'immagine."""
    h, w = frame.shape[:2]

    # Sfondo semi-trasparente per il testo
    overlay = frame.copy()
    cv2.rectangle(overlay, (0, 0), (w, 50), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.4, frame, 0.6, 0, frame)

    cv2.putText(frame, f"FPS: {fps:.1f}", (10, 32),
                cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 120), 2, cv2.LINE_AA)
    cv2.putText(frame, f"Posa: {pose_label}", (w // 2 - 80, 32),
                cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 200, 0), 2, cv2.LINE_AA)
    return frame


# ─────────────────────────────────────────────
# Pipeline principale
# ─────────────────────────────────────────────

def download_model():
    """Scarica il modello .task se non è già presente."""
    if not MODEL_PATH.exists():
        print(f"[INFO] Download modello da MediaPipe ({MODEL_URL}) ...")
        urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
        print(f"[INFO] Modello salvato in {MODEL_PATH}")
    else:
        print(f"[INFO] Modello già presente: {MODEL_PATH}")


class PoseEstimator:
    def __init__(self, config: PoseConfig, running_mode: RunningMode = RunningMode.IMAGE):
        self.config = config

        download_model()

        base_options = mp_python.BaseOptions(model_asset_path=str(MODEL_PATH))
        options = PoseLandmarkerOptions(
            base_options=base_options,
            running_mode=running_mode,
            min_pose_detection_confidence=config.MIN_DETECTION_CONF,
            min_tracking_confidence=config.MIN_TRACKING_CONF,
            min_pose_presence_confidence=config.MIN_PRESENCE_CONF,
        )
        self.landmarker = mp_vision.PoseLandmarker.create_from_options(options)

        self.frame_count = 0
        self.fps         = 0.0
        self.tick        = cv2.getTickCount()
        self.running_mode = running_mode

    def process_frame(self, frame: np.ndarray, timestamp_ms: int = 0):
        """
        Elabora un singolo frame.

        Returns:
            frame annotato, lista keypoint (o None se nessuna posa)
        """
        h, w = frame.shape[:2]
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        if self.running_mode == RunningMode.IMAGE:
            results = self.landmarker.detect(mp_image)
        else:
            results = self.landmarker.detect_for_video(mp_image, timestamp_ms)

        lm_dict = None
        if results.pose_landmarks:
            lm_dict = landmarks_to_dict_new(results.pose_landmarks[0], w, h)
            if self.config.DRAW_LANDMARKS:
                frame = draw_pose(frame, lm_dict)
            pose_label = classify_pose(lm_dict, h)
        else:
            pose_label = "Nessuna posa"

        # FPS
        self.frame_count += 1
        if self.frame_count % 10 == 0:
            now      = cv2.getTickCount()
            elapsed  = (now - self.tick) / cv2.getTickFrequency()
            self.fps = 10 / elapsed
            self.tick = now

        if self.config.SHOW_FPS:
            frame = draw_hud(frame, self.fps, pose_label)

        return frame, lm_dict

    def close(self):
        self.landmarker.close()


# ─────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────

def parse_args():
    parser = argparse.ArgumentParser(description="Pose Estimation con MediaPipe")
    parser.add_argument("--source", default="0",
                        help="Sorgente: 0/1 per webcam, path a video o immagine")
    parser.add_argument("--save",   default=None,
                        help="Path file di output (es. output.mp4 o output.jpg)")
    parser.add_argument("--json",   action="store_true",
                        help="Esporta keypoints in JSON (pose_data.json)")
    return parser.parse_args()


def run_on_image(path: str, estimator: PoseEstimator, save_path: str | None):
    frame = cv2.imread(path)
    if frame is None:
        print(f"[ERRORE] Impossibile aprire l'immagine: {path}")
        sys.exit(1)

    out, lm_dict = estimator.process_frame(frame)
    cv2.imshow("Pose Estimation", out)

    if save_path:
        cv2.imwrite(save_path, out)
        print(f"[INFO] Immagine salvata: {save_path}")

    if lm_dict:
        print(f"[INFO] Rilevati {len(lm_dict)} keypoint")
        if estimator.config.EXPORT_JSON:
            with open("pose_data.json", "w") as f:
                json.dump(lm_dict, f, indent=2)
            print("[INFO] Keypoint salvati in pose_data.json")

    print("Premi un tasto per uscire...")
    cv2.waitKey(0)
    cv2.destroyAllWindows()


def run_on_video(source, estimator: PoseEstimator, save_path: str | None):
    cap_source = int(source) if str(source).isdigit() else source
    cap = cv2.VideoCapture(cap_source)

    if not cap.isOpened():
        print(f"[ERRORE] Impossibile aprire la sorgente: {source}")
        sys.exit(1)

    w   = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    h   = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30

    writer = None
    if save_path:
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(save_path, fourcc, fps, (w, h))
        print(f"[INFO] Registrazione su {save_path}")

    all_data  = []
    frame_idx = 0

    print("[INFO] Avvio elaborazione. Premi Q per uscire.")

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        timestamp_ms = int(cap.get(cv2.CAP_PROP_POS_MSEC))
        out, lm_dict = estimator.process_frame(frame, timestamp_ms)

        if lm_dict and estimator.config.EXPORT_JSON:
            all_data.append({"frame": frame_idx, "landmarks": lm_dict})

        if writer:
            writer.write(out)

        cv2.imshow("Pose Estimation", out)
        frame_idx += 1

        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    if writer:
        writer.release()
    cv2.destroyAllWindows()

    if estimator.config.EXPORT_JSON and all_data:
        with open("pose_data.json", "w") as f:
            json.dump(all_data, f, indent=2)
        print(f"[INFO] {len(all_data)} frame salvati in pose_data.json")


def main():
    args = parse_args()

    config = PoseConfig()
    config.EXPORT_JSON = args.json

    source = args.source
    ext    = Path(source).suffix.lower() if not str(source).isdigit() else ""

    is_image = ext in (".jpg", ".jpeg", ".png", ".bmp", ".webp")
    mode     = RunningMode.IMAGE if is_image else RunningMode.VIDEO

    estimator = PoseEstimator(config, running_mode=mode)

    try:
        if is_image:
            run_on_image(source, estimator, args.save)
        else:
            run_on_video(source, estimator, args.save)
    finally:
        estimator.close()


if __name__ == "__main__":
    main()