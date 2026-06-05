import Foundation
import Vision

/// On-device text recognition for captured images (Apple Vision framework —
/// no network, no cost). Recognized text feeds the FTS index so screenshots
/// are searchable by what's written in them.
enum OCRService {
    static func recognizeText(in pngData: Data, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    completion(text.isEmpty ? nil : text)
                }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(data: pngData, options: [:])
            do {
                try handler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }
}
