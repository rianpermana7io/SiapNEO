import SwiftUI
import WebKit
import PDFKit

// MARK: - Hex Color Helper

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Theme Preferences (Matches Android ThemeState / ThemeOptionChip / UiDensityOptionChip)

enum SiapThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Terang"
        case .dark: return "Gelap"
        }
    }
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SiapUiDensity: String, CaseIterable, Identifiable {
    case standard = "STANDARD"
    case compactPro = "COMPACT_PRO"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Standar"
        case .compactPro: return "Kompak Pro"
        }
    }
}

// MARK: - Exact Port of Android ColorKt.java + SiapSemanticColors.java

struct SiapColors {
    let isDark: Bool

    // Surfaces
    let backdrop: Color
    let surface: Color
    let surfaceElevated: Color
    let cardBorder: Color
    let outline: Color
    let divider: Color

    // Typography
    let textPrimary: Color
    let textSecondary: Color
    let textHint: Color

    // Actions (Light = Navy, Dark = Amber Gold #F59E0B!)
    let primaryAction: Color
    let onPrimaryAction: Color
    let primaryContainer: Color
    let onPrimaryContainer: Color
    let secondary: Color
    let onSecondary: Color

    // Semantic Status
    let success: Color
    let danger: Color
    let warning: Color

    // Warning / Atensi Box
    let warningBoxBg: Color
    let warningBoxBorder: Color
    let warningBoxText: Color

    // My Task Highlight (TPS Monitoring)
    let myTaskBg: Color
    let myTaskBorder: Color
    let myTaskText: Color

    // Gradients
    let headerGradient: LinearGradient
    let cardGradient: LinearGradient

    // Fixed brand accents
    static let brandNavyDark = Color(hex: 0x0F2638)
    static let brandNavy = Color(hex: 0x1F3D52)
    static let brandTeal = Color(hex: 0x1F5457)
    static let brandAmber = Color(hex: 0xF59E0B)
    static let brandSky = Color(hex: 0x38BDF8)
    static let hintOnNavy = Color(hex: 0xD5E0E8)

    static let light = SiapColors(
        isDark: false,
        backdrop: Color(hex: 0xF2F4F7),
        surface: Color(hex: 0xFFFFFF),
        surfaceElevated: Color(hex: 0xEBF0F4),
        cardBorder: Color(hex: 0xD5DDE5),
        outline: Color(hex: 0x8A96A3),
        divider: Color(hex: 0xD5DDE5),
        textPrimary: Color(hex: 0x14181C),
        textSecondary: Color(hex: 0x3E4A56),
        textHint: Color(hex: 0x4B5563),
        primaryAction: Color(hex: 0x1F3D52),
        onPrimaryAction: .white,
        primaryContainer: Color(hex: 0xDCE4EC),
        onPrimaryContainer: Color(hex: 0x0F2638),
        secondary: Color(hex: 0x1F5457),
        onSecondary: .white,
        success: Color(hex: 0x166534),
        danger: Color(hex: 0x9B1C1C),
        warning: Color(hex: 0xD97706),
        warningBoxBg: Color(hex: 0xFFFBEB),
        warningBoxBorder: Color(hex: 0xF59E0B),
        warningBoxText: Color(hex: 0x92400E),
        myTaskBg: Color(hex: 0xFFFDF0),
        myTaskBorder: Color(hex: 0xF59E0B),
        myTaskText: Color(hex: 0x78350F),
        headerGradient: LinearGradient(
            colors: [Color(hex: 0x0F2638), Color(hex: 0x1F3D52), Color(hex: 0x1D4A50)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        cardGradient: LinearGradient(
            colors: [Color(hex: 0x0F2638), Color(hex: 0x173244), Color(hex: 0x1D4A50)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )

    static let dark = SiapColors(
        isDark: true,
        backdrop: Color(hex: 0x0A1118),
        surface: Color(hex: 0x121E2A),
        surfaceElevated: Color(hex: 0x1B2B3C),
        cardBorder: Color(hex: 0x1E2D3D),
        outline: Color(hex: 0x64748B),
        divider: Color(hex: 0x1E2D3D),
        textPrimary: Color(hex: 0xFFFFFF),
        textSecondary: Color(hex: 0xCBD5E1),
        textHint: Color(hex: 0x94A3B8),
        primaryAction: Color(hex: 0xF59E0B),
        onPrimaryAction: Color(hex: 0x0B131D),
        primaryContainer: Color(hex: 0x26394E),
        onPrimaryContainer: Color(hex: 0xFDE68A),
        secondary: Color(hex: 0x38BDF8),
        onSecondary: Color(hex: 0x032230),
        success: Color(hex: 0x4ADE80),
        danger: Color(hex: 0xF87171),
        warning: Color(hex: 0xFDE68A),
        warningBoxBg: Color(hex: 0x2D1B06),
        warningBoxBorder: Color(hex: 0xB45309),
        warningBoxText: Color(hex: 0xFDE68A),
        myTaskBg: Color(hex: 0x1C2819),
        myTaskBorder: Color(hex: 0xF59E0B),
        myTaskText: Color(hex: 0xFDE68A),
        headerGradient: LinearGradient(
            colors: [Color(hex: 0x081018), Color(hex: 0x121E2A), Color(hex: 0x162536)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        cardGradient: LinearGradient(
            colors: [Color(hex: 0x121E2A), Color(hex: 0x1B2B3C), Color(hex: 0x152330)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )

    static func forScheme(_ scheme: ColorScheme) -> SiapColors {
        scheme == .dark ? .dark : .light
    }

    func statusBadgeStyle(for rawStatus: String) -> (bg: Color, fg: Color, accent: Color) {
        let s = rawStatus.lowercased()
        if s.contains("selesai") || s.contains("done") || s.contains("bap") {
            return isDark
                ? (Color(hex: 0x082F49), Color(hex: 0x7DD3FC), Color(hex: 0x38BDF8))
                : (Color(hex: 0xF0F9FF), Color(hex: 0x0C4A6E), Color(hex: 0x0284C7))
        }
        if s.contains("sedang") || s.contains("proses") || s.contains("progress") {
            return isDark
                ? (Color(hex: 0x052E16), Color(hex: 0x86EFAC), Color(hex: 0x4ADE80))
                : (Color(hex: 0xECFDF5), Color(hex: 0x14532D), Color(hex: 0x16A34A))
        }
        if s.contains("siap") || s.contains("tolak") || s.contains("batal") || s.contains("belum") {
            return isDark
                ? (Color(hex: 0x450A0A), Color(hex: 0xFCA5A5), Color(hex: 0xF87171))
                : (Color(hex: 0xFEF2F2), Color(hex: 0x991B1B), Color(hex: 0xDC2626))
        }
        if s.contains("pending") || s.contains("tunda") || s.contains("hold") {
            return isDark
                ? (Color(hex: 0x451A03), Color(hex: 0xFDE68A), Color(hex: 0xF59E0B))
                : (Color(hex: 0xFFFBEB), Color(hex: 0x78350F), Color(hex: 0xD97706))
        }
        return isDark
            ? (Color(hex: 0x0F172A), Color(hex: 0xE2E8F0), Color(hex: 0x64748B))
            : (Color(hex: 0xF1F5F9), Color(hex: 0x0F172A), Color(hex: 0x64748B))
    }
}

// MARK: - Reusable SIAP NEO Shared Widgets

struct SiapStatusChip: View {
    let text: String
    let colors: SiapColors

    var body: some View {
        let st = colors.statusBadgeStyle(for: text)
        Text(text.isEmpty ? "BELUM PERIKSA" : text.uppercased())
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(st.bg)
            .foregroundStyle(st.fg)
            .overlay(
                Capsule().stroke(st.accent.opacity(colors.isDark ? 0.45 : 0.25), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

struct SiapMetaTag: View {
    let icon: String?
    let text: String
    let bg: Color
    let fg: Color

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(bg)
        .foregroundStyle(fg)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SiapFilledButton: View {
    let title: String
    let icon: String?
    let bg: Color
    let fg: Color
    let isLoading: Bool
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        bg: Color,
        fg: Color,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.bg = bg
        self.fg = fg
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView().tint(fg).scaleEffect(0.85)
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(bg)
            .foregroundStyle(fg)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SiapOutlinedButton: View {
    let title: String
    let icon: String?
    let color: Color
    let bg: Color
    let action: () -> Void

    init(
        _ title: String,
        icon: String? = nil,
        color: Color,
        bg: Color = .clear,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.color = color
        self.bg = bg
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 13.5, weight: .semibold))
                }
                Text(title).font(.system(size: 13.5, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .padding(.horizontal, 10)
            .background(bg)
            .foregroundStyle(color)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(color.opacity(0.65), lineWidth: 1.25)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live WIB Clock View (Matches HomeTopBar LiveClockText)

struct SiapLiveClockText: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let formatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "id_ID")
        df.timeZone = TimeZone(identifier: "Asia/Jakarta")
        df.dateFormat = "EEE, dd MMM • HH:mm:ss 'WIB'"
        return df
    }()

    var body: some View {
        Text(Self.formatter.string(from: now))
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(SiapColors.hintOnNavy)
            .onReceive(timer) { date in
                now = date
            }
    }
}

// MARK: - Native PDFKit Viewer & Share Sheet (Matches Android DocumentViewerKt)

struct SiapPdfKitView: UIViewRepresentable {
    let url: URL
    let rotationDegrees: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = UIColor(red: 0.04, green: 0.07, blue: 0.09, alpha: 1.0)
        if let doc = PDFDocument(url: url) {
            pdfView.document = doc
        }
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            if let doc = PDFDocument(url: url) {
                pdfView.document = doc
            }
        }
        if let doc = pdfView.document {
            let normRot = ((rotationDegrees % 360) + 360) % 360
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i), page.rotation != normRot {
                    page.rotation = normRot
                }
            }
            pdfView.layoutDocumentView()
        }
    }
}

struct SiapShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Fallback WebView

struct SiapWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 0.04, green: 0.07, blue: 0.09, alpha: 1.0)
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
