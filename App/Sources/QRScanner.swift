import SwiftUI
import UniformTypeIdentifiers
import STMCore
import STMUI
#if os(iOS)
import VisionKit
#endif
#if os(macOS)
import AppKit
import CoreImage
#endif

/// Leer el QR de invitación, como en Android. En iPhone con la cámara;
/// en Mac, desde una imagen (una captura o la foto que te mandó tu pareja).
struct ScanInviteButton: View {
    let onCode: (InviteCode) -> Void

    @State private var scanning = false
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            #if os(iOS)
            Button("Escanear QR", systemImage: "qrcode.viewfinder") { scanning = true }
                .buttonStyle(SecondaryButtonStyle())
                .sheet(isPresented: $scanning) {
                    QRCameraSheet { text in
                        if let code = InviteCode(text) {
                            scanning = false
                            onCode(code)
                        }
                    }
                }
            #else
            Button("Leer QR de una imagen", systemImage: "qrcode.viewfinder") { importing = true }
                .buttonStyle(SecondaryButtonStyle())
                .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
                    error = nil
                    guard case .success(let url) = result else { return }
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    if let text = QRImageReader.read(url), let code = InviteCode(text) {
                        onCode(code)
                    } else {
                        error = "No se encontró un QR de invitación en esa imagen."
                    }
                }
            #endif
            ErrorText(message: error)
        }
    }
}

#if os(iOS)
/// Hoja con la cámara: lee el primer QR que sea un código de invitación.
private struct QRCameraSheet: View {
    let onText: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRCameraView(onText: onText)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    Text("La cámara no está disponible o no tiene permiso. Puedes escribir el código a mano.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.labelSecondary)
                        .padding(Spacing.s24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .background(Palette.bgGrouped)
            .navigationTitle("Escanear QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
            }
            .safeAreaInset(edge: .top) {
                Text("Apunta al QR de tu pareja.")
                    .font(Typography.subheadline)
                    .foregroundStyle(Palette.labelSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.s8)
            }
        }
    }
}

private struct QRCameraView: UIViewControllerRepresentable {
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onText: (String) -> Void
        init(onText: @escaping (String) -> Void) { self.onText = onText }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let text = code.payloadStringValue { onText(text) }
            }
        }
    }
}
#endif

#if os(macOS)
enum QRImageReader {
    /// El texto del primer QR de la imagen, o nil.
    static func read(_ url: URL) -> String? {
        guard let image = CIImage(contentsOf: url),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]) else { return nil }
        return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
    }
}
#endif
