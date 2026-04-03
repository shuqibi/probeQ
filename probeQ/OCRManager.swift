import Foundation
import Vision
import AppKit

class OCRManager {
    static let shared = OCRManager()
    
    // Asynchronously returns the text parsed from the screen capture
    func captureAndRecognizeText() async throws -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent("screencapture_temp.png")
        
        // Remove old temp file if it somehow exists
        try? FileManager.default.removeItem(at: tempURL)
        
        // Execute macOS native screencapture tool
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", tempURL.path]
        
        try process.run()
        process.waitUntilExit()
        
        // If file doesn't exist, user likely pressed ESC to cancel
        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw NSError(domain: "OCRManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Screen capture was cancelled or failed."])
        }
        
        // Load the image for Vision
        guard let nsImage = NSImage(contentsOf: tempURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "OCRManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load captured image."])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                // Always clean up the temp file
                try? FileManager.default.removeItem(at: tempURL)
                
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                // Extract strings from the observations safely
                let extractedText = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")
                
                continuation.resume(returning: extractedText)
            }
            
            // Prefer accuracy over speed
            request.recognitionLevel = .accurate
            
            // Explicitly support Chinese and English parsing
            if #available(macOS 11.0, *) {
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            }
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try requestHandler.perform([request])
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                continuation.resume(throwing: error)
            }
        }
    }
}
