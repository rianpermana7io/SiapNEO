import SwiftUI

enum SiapBottomTab: String, CaseIterable, Identifiable {
    case beranda = "Beranda"
    case instruksi = "Instruksi"
    case browse = "Browse"
    case tps = "TPS"
    case akun = "Akun"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .beranda: return "house.fill"
        case .instruksi: return "shippingbox.fill"
        case .browse: return "doc.text.magnifyingglass"
        case .tps: return "ferry.fill"
        case .akun: return "person.crop.circle.fill"
        }
    }
}

struct DokapTarget: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let url: URL
}

@main
struct SIAPNeoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            SiapRootContainer()
                .environmentObject(appState)
                .preferredColorScheme(appState.themeMode.preferredColorScheme)
        }
    }
}

struct SiapRootContainer: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var colors: SiapColors { SiapColors.forScheme(colorScheme) }

    var body: some View {
        ZStack(alignment: .top) {
            colors.backdrop.ignoresSafeArea()

            if app.session != nil {
                SiapMainShell(colors: colors)
            } else {
                LoginView(colors: colors)
            }

            if let msg = app.toastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(SiapColors.brandAmber)
                    Text(msg)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(Color(hex: 0x0F2638).opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(SiapColors.brandAmber.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(200)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toastMessage)
    }
}

struct SiapMainShell: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    private var isInSubView: Bool {
        app.activeDokap != nil || app.activeUploadContext != nil || app.selectedPib != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            SiapTopAppBar(colors: colors)

            if let upd = app.availableUpdate {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(SiapColors.brandAmber)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Update SIAP NEO v\(upd.remoteVersion) tersedia!")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Tap Update untuk pasang otomatis via TrollStore")
                            .font(.system(size: 10.5))
                            .foregroundStyle(SiapColors.hintOnNavy)
                    }
                    Spacer()
                    Button {
                        app.triggerTrollStoreUpdate(upd)
                    } label: {
                        Text("Update")
                            .font(.system(size: 11.5, weight: .heavy))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(SiapColors.brandAmber)
                            .foregroundStyle(Color(hex: 0x0B131D))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        app.availableUpdate = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(SiapColors.hintOnNavy)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: 0x16293B))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(SiapColors.brandAmber.opacity(0.45)).frame(height: 1)
                }
            }

            ZStack {
                colors.backdrop.ignoresSafeArea(edges: .bottom)

                if let dokap = app.activeDokap {
                    DokapViewerPanel(target: dokap, colors: colors)
                        .transition(.opacity)
                } else if let uploadCtx = app.activeUploadContext {
                    UploadFotoPanel(pib: uploadCtx.pib, initialNokon: uploadCtx.nokon, allContainers: uploadCtx.containers, colors: colors)
                        .transition(.move(edge: .trailing))
                } else if let pib = app.selectedPib {
                    HeaderPibFclPanel(pib: pib, colors: colors)
                        .transition(.move(edge: .trailing))
                } else {
                    switch app.activeTab {
                    case .beranda:
                        HomeDashboardView(colors: colors)
                    case .instruksi:
                        LorongTabView(colors: colors)
                    case .browse:
                        BrowseTabView(colors: colors)
                    case .tps:
                        TpsTabView(colors: colors)
                    case .akun:
                        UserTabView(colors: colors)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !isInSubView {
                SiapBottomNavBar(colors: colors)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.selectedPib?.id)
        .animation(.easeInOut(duration: 0.18), value: app.activeUploadContext?.nokon)
        .animation(.easeInOut(duration: 0.18), value: app.activeDokap?.id)
        .sheet(isPresented: $app.showManualSheet) {
            ManualPibSheet(colors: colors)
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
        }
        .sheet(item: $app.barconSheetTarget) { target in
            AjuBarconFormSheet(target: target, colors: colors)
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
        }
        .task {
            await app.checkForAppUpdate(silent: true)
        }
    }
}

// MARK: - Authentic Android HomeTopBar

struct SiapTopAppBar: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    private var isSubView: Bool {
        app.activeDokap != nil || app.activeUploadContext != nil || app.selectedPib != nil
    }

    private var titleText: String {
        if let dokap = app.activeDokap {
            return dokap.title
        }
        if let up = app.activeUploadContext {
            return "Upload • \(up.nokon)"
        }
        if let pib = app.selectedPib {
            return "PIB \(pib.noPib)"
        }
        switch app.activeTab {
        case .beranda: return "SIAP NEO"
        case .instruksi: return "Instruksi Lorong"
        case .browse: return "Browse Dokumen"
        case .tps: return "Monitoring TPS"
        case .akun: return "Profil & Pengaturan"
        }
    }

    private var subtitleText: String? {
        if let up = app.activeUploadContext {
            return "PIB \(up.pib.noPib) • \(up.pib.importir)"
        }
        if let pib = app.selectedPib {
            return pib.importir
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 10) {
            if isSubView {
                Button {
                    app.navigateBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                Image("SiapLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .padding(3)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(size: 16.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if let sub = subtitleText, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(SiapColors.hintOnNavy)
                        .lineLimit(1)
                } else {
                    SiapLiveClockText()
                }
            }

            Spacer(minLength: 4)

            if !isSubView {
                if app.activeTab == .beranda {
                    Button {
                        Task { await app.loadPibs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.14))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(app.isLoadingPibs)
                }

                Button {
                    app.activeTab = .akun
                } label: {
                    SiapUserAvatarBadge(session: app.session, size: 34)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            colors.headerGradient
                .ignoresSafeArea(edges: .top)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)
        }
    }
}

struct SiapUserAvatarBadge: View {
    let session: UserSession?
    let size: CGFloat

    private var initials: String {
        let name = session?.displayName ?? "SN"
        let words = name.split(separator: " ").prefix(2)
        let res = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return res.isEmpty ? "SN" : res
    }

    var body: some View {
        ZStack {
            if let urlStr = session?.photoUrl, urlStr.hasPrefix("http"), let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        Text(initials)
                            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Text(initials)
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.18))
        .clipShape(Circle())
        .overlay(
            Circle().stroke(SiapColors.brandAmber.opacity(0.85), lineWidth: 1.5)
        )
    }
}

// MARK: - Authentic Android BottomNavBar

struct SiapBottomNavBar: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SiapBottomTab.allCases) { tab in
                let isSelected = app.activeTab == tab
                Button {
                    app.activeTab = tab
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(colors.primaryContainer)
                                    .frame(width: 48, height: 28)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                                .foregroundStyle(isSelected ? colors.primaryAction : colors.textHint)
                        }
                        .frame(height: 28)

                        Text(tab.rawValue)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? colors.primaryAction : colors.textHint)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .background(
            colors.surface
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colors.divider)
                .frame(height: 0.75)
        }
    }
}
