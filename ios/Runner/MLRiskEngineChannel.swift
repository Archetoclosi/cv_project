import CoreML
import Flutter

/// Swift wrapper che carica RiskEngine.mlmodel e lo espone a Flutter
/// tramite un MethodChannel.
///
/// Canale: "com.yourapp/ml_risk_engine"
/// Metodo: "predict" — riceve una Map<String, Double> di feature,
///          restituisce una Map con "risk_label" (Int) e "threat_probability" (Double).
///
/// Setup in AppDelegate.swift:
///   MLRiskEngineChannel.register(with: flutterEngine.binaryMessenger)
@objc class MLRiskEngineChannel: NSObject {

    static let channelName = "com.yourapp/ml_risk_engine"

    private var model: MLModel?

    // Feature names — devono corrispondere a FEATURE_COLS in train.py
    static let featureCols = [
        "phone_detected", "phone_confidence", "phone_persistence",
        "phone_area_ratio", "phone_center_x", "phone_center_y",
        "face_detected", "face_count",
        "accel_magnitude_mean", "accel_magnitude_std",
        "gyro_magnitude_mean", "gyro_magnitude_std",
        "tilt_angle", "mag_magnitude_std",
        "is_stationary", "tilt_in_photo_range", "phone_strength",
    ]

    override init() {
        super.init()
        loadModel()
    }

    // MARK: - Registration

    static func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: messenger
        )
        let instance = MLRiskEngineChannel()
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "predict":
                guard let args = call.arguments as? [String: Any] else {
                    result(FlutterError(
                        code: "INVALID_ARGS",
                        message: "Expected Map<String, Any>",
                        details: nil
                    ))
                    return
                }
                instance.predict(args: args, result: result)

            case "isModelLoaded":
                result(instance.model != nil)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    // MARK: - Model loading

    private func loadModel() {
        guard let modelURL = Bundle.main.url(
            forResource: "RiskEngine",
            withExtension: "mlmodelc"  // compilato da Xcode automaticamente
        ) else {
            print("[MLRiskEngine] ⚠️ RiskEngine.mlmodelc non trovato nel bundle.")
            print("[MLRiskEngine] Assicurati di aver copiato RiskEngine.mlmodel in ios/Runner/")
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all  // usa ANE + GPU + CPU automaticamente
            model = try MLModel(contentsOf: modelURL, configuration: config)
            print("[MLRiskEngine] ✅ Modello caricato correttamente.")
        } catch {
            print("[MLRiskEngine] ❌ Errore caricamento modello: \(error)")
        }
    }

    // MARK: - Inference

    private func predict(args: [String: Any], result: @escaping FlutterResult) {
        guard let model = model else {
            // Fallback: modello non disponibile → restituisce -1
            // Il Dart layer intercetterà questo e userà il rule-based engine
            result(["risk_label": -1, "threat_probability": -1.0])
            return
        }

        // Costruisce il provider di feature da args
        let provider: MLFeatureProvider
        do {
            provider = try buildFeatureProvider(from: args)
        } catch {
            result(FlutterError(
                code: "FEATURE_ERROR",
                message: "Errore costruzione feature: \(error.localizedDescription)",
                details: nil
            ))
            return
        }

        // Inferenza
        do {
            let prediction = try model.prediction(from: provider)
            let label = prediction.featureValue(for: "risk_label")?.int64Value ?? 0
            let probDict = prediction.featureValue(for: "classProbability")?.dictionaryValue
            let threatProb = probDict?[1 as NSNumber] as? Double ?? 0.0

            result([
                "risk_label": label,
                "threat_probability": threatProb,
            ])
        } catch {
            result(FlutterError(
                code: "INFERENCE_ERROR",
                message: "Errore inferenza: \(error.localizedDescription)",
                details: nil
            ))
        }
    }

    private func buildFeatureProvider(from args: [String: Any]) throws -> MLFeatureProvider {
        var features: [String: MLFeatureValue] = [:]

        for col in Self.featureCols {
            let value: Double
            if let v = args[col] as? Double {
                value = v
            } else if let v = args[col] as? Int {
                value = Double(v)
            } else if let v = args[col] as? Bool {
                value = v ? 1.0 : 0.0
            } else {
                // Feature mancante → 0.0 come default sicuro
                print("[MLRiskEngine] ⚠️ Feature mancante: \(col), uso 0.0")
                value = 0.0
            }
            features[col] = MLFeatureValue(double: value)
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }
}
