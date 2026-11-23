import SwiftUI
import UIKit
import CoreLocation
import Vision

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var coordinateText: String = "0.0,0.0"

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func request() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let lat = String(format: "%.6f", loc.coordinate.latitude)
        let lon = String(format: "%.6f", loc.coordinate.longitude)
        DispatchQueue.main.async {
            self.coordinateText = "\(lat),\(lon)"
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep last known or default
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onPicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.onPicked(img)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

enum ImageWatermarkProcessor {
    static func process(
        image: UIImage,
        maxDimension: CGFloat = 1600,
        watermark: Bool,
        noPib: String,
        nokon: String,
        stepLabel: String,
        lokasi: String
    ) -> Data? {
        let origSize = image.size
        let scale = min(maxDimension / max(origSize.width, 1), maxDimension / max(origSize.height, 1), 1.0)
        let targetSize = CGSize(width: max(1, floor(origSize.width * scale)), height: max(1, floor(origSize.height * scale)))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        let rendered = renderer.image { ctx in
            image.draw(in: CGRect(origin: .zero, size: targetSize))

            guard watermark else { return }

            let fontSize = max(16, min(targetSize.width, targetSize.height) * 0.025)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
            let headerParts = [noPib.isEmpty ? "" : "PIB \(noPib)", nokon].filter { !$0.isEmpty }
            var lines: [String] = [SiapCrypto.currentDisplayClock()]
            if !headerParts.isEmpty { lines.append(headerParts.joined(separator: " | ")) }
            if !stepLabel.isEmpty { lines.append(stepLabel) }
            if !lokasi.isEmpty && lokasi != "0.0,0.0" { lines.append("GPS: \(lokasi)") }

            let lineAttrs: [[NSAttributedString.Key: Any]] = lines.enumerated().map { idx, _ in
                [
                    .font: font,
                    .foregroundColor: idx == 0
                        ? UIColor(red: 0.49, green: 0.83, blue: 0.99, alpha: 1.0)
                        : UIColor.white
                ]
            }

            let sizes = zip(lines, lineAttrs).map { ($0 as NSString).size(withAttributes: $1) }
            let padX = fontSize * 0.8
            let padY = fontSize * 0.5
            let gap = fontSize * 0.3
            let boxW = (sizes.map(\.width).max() ?? 100) + padX * 2
            let boxH = sizes.map(\.height).reduce(0, +) + gap * CGFloat(max(0, lines.count - 1)) + padY * 2

            let margin = fontSize * 0.7
            let rect = CGRect(x: margin, y: max(margin, targetSize.height - boxH - margin), width: boxW, height: boxH)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: fontSize * 0.5)
            UIColor(red: 0.04, green: 0.07, blue: 0.13, alpha: 0.72).setFill()
            path.fill()

            var cy = rect.minY + padY
            for i in 0..<lines.count {
                (lines[i] as NSString).draw(at: CGPoint(x: rect.minX + padX, y: cy), withAttributes: lineAttrs[i])
                cy += sizes[i].height + gap
            }
        }
        return rendered.jpegData(compressionQuality: 0.90)
    }
}

enum ContainerOcrScanner {
    static func scanContainerNumber(from image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }
        return await withCheckedContinuation { cont in
            let req = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let allText = observations.compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: " ")
                    .uppercased()
                    .replacingOccurrences(of: " ", with: "")
                if let regex = try? NSRegularExpression(pattern: "([A-Z]{4}\\d{7})"),
                   let match = regex.firstMatch(in: allText, range: NSRange(location: 0, length: (allText as NSString).length)) {
                    let found = (allText as NSString).substring(with: match.range(at: 1))
                    cont.resume(returning: found)
                } else {
                    cont.resume(returning: nil)
                }
            }
            req.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([req])
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

final class SignatureStrokeStore: ObservableObject {
    @Published var strokes: [[CGPoint]] = []

    var isEmpty: Bool { strokes.isEmpty }

    func clear() {
        strokes.removeAll()
    }

    func renderImage(size: CGSize = CGSize(width: 600, height: 240)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            UIColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1.0).setStroke()
            ctx.cgContext.setLineWidth(3.5)
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.setLineJoin(.round)

            for stroke in strokes where stroke.count > 1 {
                ctx.cgContext.beginPath()
                ctx.cgContext.move(to: CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height))
                for pt in stroke.dropFirst() {
                    ctx.cgContext.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
                }
                ctx.cgContext.strokePath()
            }
        }
    }
}

struct SignaturePadView: View {
    @ObservedObject var store: SignatureStrokeStore
    @State private var currentStroke: [CGPoint] = []

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            let h = max(geo.size.height, 1)
            ZStack {
                Color.white
                Canvas { context, size in
                    for stroke in store.strokes where stroke.count > 1 {
                        var path = Path()
                        path.move(to: CGPoint(x: stroke[0].x * size.width, y: stroke[0].y * size.height))
                        for pt in stroke.dropFirst() {
                            path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
                        }
                        context.stroke(path, with: .color(.black), lineWidth: 3)
                    }
                    if currentStroke.count > 1 {
                        var path = Path()
                        path.move(to: CGPoint(x: currentStroke[0].x * size.width, y: currentStroke[0].y * size.height))
                        for pt in currentStroke.dropFirst() {
                            path.addLine(to: CGPoint(x: pt.x * size.width, y: pt.y * size.height))
                        }
                        context.stroke(path, with: .color(.black), lineWidth: 3)
                    }
                }
            }
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.35), lineWidth: 1))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        let norm = CGPoint(
                            x: min(max(val.location.x / w, 0), 1),
                            y: min(max(val.location.y / h, 0), 1)
                        )
                        currentStroke.append(norm)
                    }
                    .onEnded { _ in
                        if currentStroke.count > 1 {
                            store.strokes.append(currentStroke)
                        }
                        currentStroke = []
                    }
            )
        }
        .frame(height: 150)
    }
}
