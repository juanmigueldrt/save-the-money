import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// QR de un texto, nítido a cualquier tamaño.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.makeImage(text) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Código QR para unirse al hogar")
        } else {
            Color.clear
        }
    }

    static func makeImage(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
