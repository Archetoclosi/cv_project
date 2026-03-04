import cv2
from ultralytics import YOLO

# Carica il modello (usa la versione Nano per velocità)
model = YOLO('yolov8n.pt') 

# Apre la webcam del tuo PC
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("ERRORE: Non riesco ad accedere alla webcam. Controlla se è usata da altre app (Teams, Zoom, Chrome).")
else:
    print("Webcam connessa correttamente. Avvio AI...")

while cap.isOpened():
    success, frame = cap.read()
    if success:
        # Esegue la detection
        results = model(frame, conf=0.5) # Soglia 50%
        
        # Disegna i risultati (label e box) sul frame
        annotated_frame = results[0].plot()
        
        # Mostra il video in una finestra
        cv2.imshow("Test AI Anti-Screenshot", annotated_frame)
        
        # Se rileva un telefono, stampa un avviso nel terminale di VS
        for result in results:
            for box in result.boxes:
                label = model.names[int(box.cls[0])]
                if label == 'cell phone':
                    print("!!! VIOLAZIONE: Rilevato Smartphone esterno !!!")

        if cv2.waitKey(1) & 0xFF == ord("q"):
            break
    else:
        break

cap.release()
cv2.destroyAllWindows()