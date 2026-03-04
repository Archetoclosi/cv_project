from ultralytics import YOLO

# Carica il modello che hai appena testato
model = YOLO('yolov8n.pt') 

# Esporta in formato TensorFlow Lite (ottimizzato per smartphone)
# imgsz=320 lo rende velocissimo su mobile
model.export(format='tflite', imgsz=320, int8=True)