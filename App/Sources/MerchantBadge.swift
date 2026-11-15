import STMCore
import STMUI
import SwiftUI

/// Logo del comercio reconocido en la descripción, o el icono de la categoría si no hay.
/// Sólo el dominio del comercio (p. ej. apple.com) sale del dispositivo para pedir el logo.
struct MerchantBadge: View {
    let description: String
    var categoryIcon: String?
    var size: CGFloat = 36

    @State private var logo: Image?

    private var merchant: Merchant? { MerchantDirectory.match(description) }
    private var fallbackSymbol: String { merchant?.symbol ?? categoryIcon ?? "creditcard" }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Palette.bgGrouped3)
            if let logo {
                logo.resizable().scaledToFit().padding(size * 0.16)
            } else {
                symbol
            }
        }
        .frame(width: size, height: size)
        .task(id: merchant?.domain) {
            logo = nil
            logo = await LogoCache.shared.data(for: merchant).flatMap(LogoCache.makeImage)
        }
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .accessibilityHidden(true)
    }

    private var symbol: some View {
        Image(systemName: fallbackSymbol)
            .font(.system(size: size * 0.42, weight: .medium))
            .foregroundStyle(Palette.accentText)
    }
}

/// Logos guardados en el dispositivo: cada dominio se descarga una vez y se reutiliza
/// (memoria + carpeta de cachés). Si falla, se vuelve a intentar en la próxima sesión.
actor LogoCache {
    static let shared = LogoCache()

    private let token = AppConfig.fromBundle().logoDevToken
    private var memory: [String: Data] = [:]
    private var failed: Set<String> = []
    private let folder: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent(
        MerchantDirectory.publishableToken(AppConfig.fromBundle().logoDevToken) == nil ? "logos" : "logos-logodev",
        isDirectory: true)

    func data(for merchant: Merchant?) async -> Data? {
        guard let merchant, let domain = merchant.domain, let url = merchant.logoURL(logoDevToken: token) else { return nil }
        return await data(domain: domain, url: url)
    }

    private func data(domain: String, url: URL) async -> Data? {
        if let cached = memory[domain] { return cached }
        let file = folder?.appendingPathComponent(domain + ".png")
        if let file, let stored = try? Data(contentsOf: file) {
            memory[domain] = stored
            return stored
        }
        guard !failed.contains(domain) else { return nil }
        // Sin cookies ni caché compartida: al servicio sólo le llega el dominio.
        let session = URLSession(configuration: .ephemeral)
        guard let (downloaded, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, Self.makeImage(downloaded) != nil else {
            failed.insert(domain)
            return nil
        }
        memory[domain] = downloaded
        if let folder, let file {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? downloaded.write(to: file, options: .atomic)
        }
        return downloaded
    }

    nonisolated static func makeImage(_ data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map { Image(nsImage: $0) }
        #else
        UIImage(data: data).map { Image(uiImage: $0) }
        #endif
    }
}
