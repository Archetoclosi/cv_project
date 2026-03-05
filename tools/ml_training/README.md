# ML Training Pipeline — Risk Engine

## Prerequisiti

- macOS (obbligatorio per coremltools e Xcode)
- Python 3.10 o 3.11
- Xcode installato

---

## 1. Setup ambiente Python

```bash
# Dalla cartella tools/ del progetto
cd tools/

python3 -m venv .venv
source .venv/bin/activate

pip install -r requirements.txt
```

Verifica che tutto sia installato:
```bash
python -c "import sklearn, coremltools, pandas; print('OK')"
```

---

## 2. Raccogli i dati dall'app

Esegui l'app in debug, usa il pannello **DATA COLLECTION** per etichettare
i sample. Esporta il CSV via Files app o AirDrop.

Obiettivo minimo: **200 sample, bilanciati ~50/50 threat/safe**.

---

## 3. Training

```bash
# Con il venv attivo
python train.py --data /path/to/risk_engine_training_data.csv

# Output personalizzato
python train.py \
  --data /path/to/risk_engine_training_data.csv \
  --output RiskEngine.mlmodel
```

Lo script stampa:
- Statistiche del dataset (bilanciamento)
- AUC-ROC in cross-validation
- Classification report sul test set
- Feature importance (per validare che i segnali giusti pesino di più)
- Dimensione del .mlmodel generato

---

## 4. Copia il modello nell'app iOS

```bash
cp RiskEngine.mlmodel ../ios/Runner/RiskEngine.mlmodel
```

In Xcode:
1. Apri `ios/Runner.xcworkspace`
2. Trascina `RiskEngine.mlmodel` nel gruppo `Runner` nel Project Navigator
3. Spunta **"Add to targets: Runner"**
4. Xcode compila automaticamente il modello in `RiskEngine.mlmodelc`

---

## 5. Registra il MethodChannel in AppDelegate.swift

```swift
// ios/Runner/AppDelegate.swift
import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    MLRiskEngineChannel.register(with: controller.binaryMessenger)
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

---

## 6. Sostituisci RiskEngine con MLRiskEngine in Flutter

```dart
// Prima
final engine = RiskEngine();
final score = engine.evaluate(featureVector);

// Dopo
final engine = MLRiskEngine();
await engine.checkModelAvailable(); // una volta all'init
final score = await engine.evaluate(featureVector);
```

Il fallback al rule-based engine è automatico se il modello non è disponibile.

---

## Struttura file

```
tools/
  train.py                    ← training pipeline
  requirements.txt            ← dipendenze Python
  .venv/                      ← ambiente virtuale (non committare)
  RiskEngine.mlmodel          ← output del training (non committare)
  risk_engine_sklearn.joblib  ← backup scikit-learn (non committare)

ios/Runner/
  MLRiskEngineChannel.swift   ← wrapper Swift
  RiskEngine.mlmodel          ← modello da deployare

lib/services/
  ml_risk_engine.dart         ← client Dart
```

---

## Interpretare i risultati del training

| Metrica | Valore accettabile | Note |
|---|---|---|
| AUC-ROC CV | > 0.85 | Sotto 0.75: servono più dati |
| Precision threat | > 0.80 | Falsi positivi (disturbo utente) |
| Recall threat | > 0.75 | Falsi negativi (minacce non rilevate) |

Se i risultati sono sotto soglia:
- Raccogli più sample (specialmente della classe minoritaria)
- Controlla la feature importance: se `phone_detected` non è in cima, c'è un problema nei dati
- Abbassa `max_depth` se vedi overfitting (train >> test score)

---

## .gitignore consigliato per tools/

```
.venv/
*.joblib
*.mlmodel
__pycache__/
*.pyc
```
