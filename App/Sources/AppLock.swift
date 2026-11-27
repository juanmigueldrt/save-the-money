import SwiftUI
import LocalAuthentication
import STMUI

/// Bloqueo de la app con Face ID, Touch ID o el código del dispositivo (Más opciones > Seguridad).
/// Protege la pantalla de este dispositivo, no los datos.
enum AppLock {
    static let enabledKey = "stm.lock.enabled"
    /// Tiempo en segundo plano que se perdona antes de volver a pedir desbloqueo.
    static let gracePeriod: TimeInterval = 60

    /// Regla del bloqueo. `backgroundedAt` nil: no ha pasado por segundo plano.
    /// Si el reloj ha ido hacia atrás se bloquea: ante la duda, se pide.
    static func shouldLock(enabled: Bool, backgroundedAt: Date?, now: Date, grace: TimeInterval = gracePeriod) -> Bool {
        guard enabled, let backgroundedAt else { return false }
        let elapsed = now.timeIntervalSince(backgroundedAt)
        return elapsed < 0 || elapsed >= grace
    }

    /// Por qué no se puede activar en este dispositivo, o nil si se puede.
    /// `.deviceOwnerAuthentication` acepta biometría y, si no hay o falla, el código del dispositivo.
    static func unavailableReason() -> String? {
        var error: NSError?
        if LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) { return nil }
        #if os(macOS)
        return String(localized: "No disponible: este Mac no tiene Touch ID ni contraseña de usuario.")
        #else
        return String(localized: "No disponible: configura un código en el dispositivo para poder usarlo.")
        #endif
    }

    /// Las capturas del diseño nunca salen bloqueadas ni tapadas.
    static var isCapture: Bool {
        #if DEBUG
        ScreenshotMode.isActive
        #else
        false
        #endif
    }

    static func authenticate(reason: String) async -> Bool {
        (try? await LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// Único sitio donde vive el estado del bloqueo. La comprobación y el desbloqueo se inyectan para las pruebas.
@MainActor @Observable
final class AppLockModel {
    /// El de la app: lo comparten todas sus ventanas, los enlaces y los atajos. En capturas nunca bloquea.
    static let shared = AppLock.isCapture ? AppLockModel(isEnabled: { false }) : AppLockModel()

    /// Se decide al crearlo: si está activado, la app arranca ya bloqueada y no se ve nada ni un instante.
    private(set) var isLocked: Bool
    /// Al arrancar cuenta como si hubiera estado fuera desde siempre.
    private var backgroundedAt: Date? = .distantPast
    private var isAuthenticating = false
    /// Enlaces y atajos que llegaron con la app bloqueada: se hacen al desbloquear.
    private var pending: [() -> Void] = []
    private let isEnabled: () -> Bool
    private let authenticate: () async -> Bool

    init(isEnabled: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: AppLock.enabledKey) && AppLock.unavailableReason() == nil
         },
         authenticate: @escaping () async -> Bool = { await AppLock.authenticate(reason: String(localized: "Desbloquea Save the Money")) }) {
        self.isEnabled = isEnabled
        self.authenticate = authenticate
        isLocked = isEnabled()
    }

    func sceneChanged(to phase: ScenePhase, now: Date = .now) async {
        switch phase {
        case .background:
            // El diálogo del sistema no cuenta como salir de la app.
            if backgroundedAt == nil && !isAuthenticating { backgroundedAt = now }
        case .active:
            let since = backgroundedAt
            backgroundedAt = nil
            if AppLock.shouldLock(enabled: isEnabled(), backgroundedAt: since, now: now) {
                isLocked = true
                await unlock()
            }
        default:
            break
        }
    }

    /// Hace `action` ya, o al desbloquear si la app está bloqueada o va a bloquearse al volver.
    func whenUnlocked(now: Date = .now, _ action: @escaping () -> Void) {
        if isLocked || AppLock.shouldLock(enabled: isEnabled(), backgroundedAt: backgroundedAt, now: now) {
            pending.append(action)
        } else {
            action()
        }
    }

    func unlock() async {
        // Nunca deja fuera: si ya no hay biometría ni código, se abre sin pedir nada.
        guard isEnabled() else { open(); return }
        guard !isAuthenticating else { return }
        isAuthenticating = true
        if await authenticate() { open() }
        isAuthenticating = false
    }

    private func open() {
        isLocked = false
        // Lo que pasó con la app tapada (en Mac, sus ventanas escondidas) no cuenta como haber salido.
        backgroundedAt = nil
        let actions = pending
        pending = []
        actions.forEach { $0() }
    }
}

/// Tapa la app mientras está bloqueada y, en iPhone, también mientras no está activa (miniatura del selector de apps).
/// `appPhase` es la fase de toda la app, no la de cada ventana.
struct AppLockModifier: ViewModifier {
    let appPhase: ScenePhase
    @AppStorage(AppLock.enabledKey) private var enabled = false
    private let lock = AppLockModel.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if AppLock.isCapture {
            content
        } else {
            guarded(content)
        }
    }

    private var covered: Bool {
        #if os(macOS)
        // En Mac no hay miniatura de la app en el selector: una ventana visible se ve igual en el escritorio.
        lock.isLocked
        #else
        lock.isLocked || (enabled && appPhase != .active)
        #endif
    }

    private func guarded(_ content: Content) -> some View {
        content
            .accessibilityHidden(covered)
            // Tapa la vista raíz desde el primer fotograma; la ventana de encima tapa además hojas, alertas y menús.
            .overlay {
                if covered { AppLockCover(lock: lock) }
            }
            .onChange(of: appPhase, initial: true) { _, phase in
                Task { await lock.sceneChanged(to: phase) }
            }
            .onChange(of: [covered, lock.isLocked], initial: true) { _, state in
                AppLockCoverWindow.update(covered: state[0], isLocked: state[1], lock: lock)
            }
    }
}

#if os(iOS)
/// Una ventana propia por encima de las alertas: tapa también hojas, alertas y menús presentados
/// sobre la vista raíz, que un `.overlay` no alcanza, y recibe todos los toques.
@MainActor
enum AppLockCoverWindow {
    private static var windows: [UIWindow] = []
    private static var state = (covered: false, isLocked: false)
    private static var observer: NSObjectProtocol?

    static func update(covered: Bool, isLocked: Bool, lock: AppLockModel) {
        state = (covered, isLocked)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if isLocked {
            // Quita el teclado: que no quede encima ni siga escribiendo en el formulario de debajo (lo escrito se conserva).
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        if covered {
            for scene in scenes where !windows.contains(where: { $0.windowScene === scene }) {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.rootViewController = UIHostingController(rootView: AppLockCover(lock: lock))
                window.isHidden = false
                windows.append(window)
            }
        } else if !windows.isEmpty {
            windows.forEach { $0.isHidden = true }
            windows.removeAll()
            scenes.flatMap(\.windows).first { $0.windowLevel == .normal }?.makeKey()
        }
        applyFocus()
        // Si otra ventana de la app se hace principal (al arrancar, o una alerta nueva), la tapa lo vuelve a ser.
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UIWindow.didBecomeKeyNotification, object: nil,
                                                              queue: .main) { _ in
                MainActor.assumeIsolated { applyFocus() }
            }
        }
    }

    private static func applyFocus() {
        let all = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        // VoiceOver sólo lee la tapa.
        for window in all where !windows.contains(window) {
            window.accessibilityElementsHidden = state.covered
        }
        // Bloqueada, el teclado físico también va a la tapa.
        if state.isLocked, let cover = windows.first, !cover.isKeyWindow { cover.makeKey() }
    }
}
#elseif os(macOS)
/// Esconde todas las ventanas de la app (y con ellas sus hojas) y enseña una sola ventana de desbloqueo,
/// que se queda con el teclado: los atajos del menú no encuentran ninguna ventana de la app.
@MainActor
enum AppLockCoverWindow {
    private static var panel: NSWindow?
    private static var hidden: [NSWindow] = []
    private static var previousKey: NSWindow?
    private static var observer: NSObjectProtocol?

    static func update(covered: Bool, isLocked: Bool, lock: AppLockModel) {
        if covered {
            if panel == nil {
                previousKey = NSApp.keyWindow
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                                      styleMask: [.titled], backing: .buffered, defer: false)
                window.title = "Save the Money"
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: AppLockCover(lock: lock))
                window.center()
                panel = window
                // Una ventana que aparece después (la principal al arrancar, otra hoja) también se esconde.
                observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil,
                                                                  queue: .main) { _ in
                    MainActor.assumeIsolated { hideOthers() }
                }
            }
            hideOthers()
        } else if let window = panel {
            observer.map(NotificationCenter.default.removeObserver)
            observer = nil
            window.orderOut(nil)
            panel = nil
            hidden.forEach { $0.orderFront(nil) }
            (previousKey ?? hidden.first)?.makeKeyAndOrderFront(nil)
            hidden.removeAll()
            previousKey = nil
        }
    }

    private static func hideOthers() {
        guard let panel else { return }
        // Las hojas se esconden y vuelven con su ventana.
        for window in NSApp.windows where window !== panel && window.isVisible && window.sheetParent == nil {
            window.orderOut(nil)
            if !hidden.contains(window) { hidden.append(window) }
        }
        if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
    }
}
#endif

/// Lo que se ve en la tapa: sólo el candado mientras la app no está activa, y el botón cuando está bloqueada.
private struct AppLockCover: View {
    let lock: AppLockModel

    var body: some View {
        VStack(spacing: Spacing.s16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.labelSecondary)
                .accessibilityHidden(true)
            if lock.isLocked {
                Text("Save the Money está bloqueada")
                    .font(Typography.body)
                    .foregroundStyle(Palette.label)
                Button("Desbloquear") { Task { await lock.unlock() } }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Spacing.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.bgGrouped.ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}

/// Sección «Seguridad» de Más opciones.
struct AppLockSection: View {
    @AppStorage(AppLock.enabledKey) private var enabled = false
    @State private var unavailableReason = AppLock.unavailableReason()

    var body: some View {
        Section {
            Toggle("Pedir Face ID, Touch ID o código", isOn: $enabled)
                .disabled(unavailableReason != nil && !enabled)
        } header: {
            Text("Seguridad")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.s4) {
                if let unavailableReason { Text(unavailableReason) }
                Text(Self.footer)
            }
        }
    }

    private static var footer: String {
        #if os(macOS)
        let cover = String(localized: "Bloqueada, esconde todas sus ventanas. ")
        #else
        let cover = String(localized: "También tapa la app en el selector de apps. ")
        #endif
        return String(localized: "Al abrir la app y al volver tras más de un minuto fuera. ") + cover
            + String(localized: "Protege la pantalla de este dispositivo, no los datos: tu hogar los sigue viendo en los suyos.")
    }
}
