import SwiftUI
import UIKit

// MARK: - iOS 16+ Wrapping FlowLayout (Matches Jetpack Compose FlowRow)

struct TpsFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 2

    private func measuredSize(for subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        if maxWidth.isFinite && ideal.width > maxWidth {
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        return ideal
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: maxWidth)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentY += lineHeight + verticalSpacing
                currentX = 0
                lineHeight = 0
            }
            totalWidth = max(totalWidth, currentX + size.width)
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(totalWidth, maxWidth), height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        struct PlacedItem {
            let subview: LayoutSubview
            let size: CGSize
            let x: CGFloat
        }

        var lines: [[PlacedItem]] = []
        var lineHeights: [CGFloat] = []
        var currentLine: [PlacedItem] = []
        var currentX: CGFloat = 0
        var currentLineHeight: CGFloat = 0

        for subview in subviews {
            let size = measuredSize(for: subview, maxWidth: bounds.width)
            if currentX > 0 && currentX + size.width > bounds.width {
                lines.append(currentLine)
                lineHeights.append(currentLineHeight)
                currentLine = []
                currentX = 0
                currentLineHeight = 0
            }
            currentLine.append(PlacedItem(subview: subview, size: size, x: currentX))
            currentX += size.width + horizontalSpacing
            currentLineHeight = max(currentLineHeight, size.height)
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
            lineHeights.append(currentLineHeight)
        }

        var y = bounds.minY
        for (idx, line) in lines.enumerated() {
            let lh = lineHeights[idx]
            for item in line {
                let centeredY = y + (lh - item.size.height) / 2
                item.subview.place(
                    at: CGPoint(x: bounds.minX + item.x, y: centeredY),
                    proposal: ProposedViewSize(item.size)
                )
            }
            y += lh + verticalSpacing
        }
    }
}

// MARK: - Category Segment Descriptor (Matches Android TpsCategoryItem)

private struct TpsCategorySegment: Identifiable {
    let id: Int
    let title: String
    let count: Int
    let activeLight: Color
    let activeDark: Color
    let activeFgDark: Color

    init(
        id: Int,
        title: String,
        count: Int,
        activeLight: Color,
        activeDark: Color,
        activeFgDark: Color = .white
    ) {
        self.id = id
        self.title = title
        self.count = count
        self.activeLight = activeLight
        self.activeDark = activeDark
        self.activeFgDark = activeFgDark
    }
}

// MARK: - Tab 4: TPS Monitoring Hub (1:1 Parity with Android TpsMonitoringScreensKt)

struct TpsTabView: View {
    @EnvironmentObject var app: AppState
    let colors: SiapColors

    @State private var selectedCategoryIndex: Int = 0
    @State private var searchQuery: String = ""
    @State private var isSearchExpanded: Bool = false

    @State private var grahaSort: GrahaSortOption = .default
    @State private var npctSort: NpctSortOption = .siapPeriksaDesc
    @State private var tpslSort: TpslSortOption = .default

    @State private var lampiranTarget: TpsLampiranTarget?

    private var source: TpsSource { app.activeTpsSource }
    private var snapshot: TpsMonitorSnapshot { app.tpsSnapshot }
    private var isSearchVisible: Bool { isSearchExpanded || !searchQuery.isEmpty }

    // MARK: - Precomputed Counts (Matches TpsMonitoringHubScreen)

    private var grahaRaw: [GrahaMonitorItem] { snapshot.grahaRows }
    private var npctRaw: [NpctMonitorItem] { snapshot.npctRows }
    private var tpslRaw: [TpslMonitorItem] { snapshot.tpslRows }

    private var grahaSiapCount: Int { grahaRaw.filter { TpsFilterAndSort.matchesStatus($0.status, filter: .siap) }.count }
    private var grahaSedangCount: Int { grahaRaw.filter { TpsFilterAndSort.matchesStatus($0.status, filter: .sedang) }.count }
    private var grahaPpkCount: Int { grahaRaw.filter { TpsFilterAndSort.matchesStatus($0.status, filter: .ppk) }.count }
    private var grahaCount20: Int { grahaRaw.filter { $0.size.contains("20") }.count }
    private var grahaCount40: Int { grahaRaw.filter { $0.size.contains("40") || $0.size.contains("45") }.count }

    private var npctSiapCount: Int { npctRaw.filter { TpsFilterAndSort.matchesStatus($0.status, filter: .siap) }.count }
    private var npctSedangCount: Int { npctRaw.filter { TpsFilterAndSort.matchesStatus($0.status, filter: .sedang) }.count }
    private var npctPpkCount: Int { npctRaw.filter { TpsFilterAndSort.matchesStatus($0.status, filter: .ppk) }.count }
    private var npctCount20: Int { npctRaw.filter { $0.size.contains("20") }.count }
    private var npctCount40: Int { npctRaw.filter { $0.size.contains("40") || $0.size.contains("45") }.count }

    private var tpslClusters: [String] { TpsFilterAndSort.tpslClusters(for: tpslRaw) }

    private var showNpctImporterWarning: Bool {
        source == .npct
            && !npctRaw.isEmpty
            && npctRaw.allSatisfy { $0.importir.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var activeCategories: [TpsCategorySegment] {
        switch source {
        case .graha:
            return [
                TpsCategorySegment(id: 0, title: "SEMUA", count: grahaRaw.count, activeLight: SiapColors.brandNavy, activeDark: colors.primaryAction, activeFgDark: colors.onPrimaryAction),
                TpsCategorySegment(id: 1, title: "SIAP", count: grahaSiapCount, activeLight: Color(hex: 0xDC2626), activeDark: Color(hex: 0xEF4444)),
                TpsCategorySegment(id: 2, title: "PROSES", count: grahaSedangCount, activeLight: Color(hex: 0x15803D), activeDark: Color(hex: 0x10B981)),
                TpsCategorySegment(id: 3, title: "PPK", count: grahaPpkCount, activeLight: Color(hex: 0xD97706), activeDark: Color(hex: 0xF59E0B), activeFgDark: Color(hex: 0x0B131D))
            ]
        case .npct:
            return [
                TpsCategorySegment(id: 0, title: "SEMUA", count: npctRaw.count, activeLight: SiapColors.brandNavy, activeDark: colors.primaryAction, activeFgDark: colors.onPrimaryAction),
                TpsCategorySegment(id: 1, title: "SIAP", count: npctSiapCount, activeLight: Color(hex: 0xDC2626), activeDark: Color(hex: 0xEF4444)),
                TpsCategorySegment(id: 2, title: "PROSES", count: npctSedangCount, activeLight: Color(hex: 0x15803D), activeDark: Color(hex: 0x10B981)),
                TpsCategorySegment(id: 3, title: "PPK", count: npctPpkCount, activeLight: Color(hex: 0xD97706), activeDark: Color(hex: 0xF59E0B), activeFgDark: Color(hex: 0x0B131D))
            ]
        case .tpsl:
            return tpslClusters.enumerated().map { idx, cluster in
                let cnt: Int
                if cluster == "SEMUA" {
                    cnt = tpslRaw.count
                } else {
                    cnt = tpslRaw.filter {
                        $0.cluster.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(cluster) == .orderedSame
                    }.count
                }
                if cluster == "SEMUA" {
                    return TpsCategorySegment(id: idx, title: "SEMUA", count: cnt, activeLight: SiapColors.brandNavy, activeDark: colors.primaryAction, activeFgDark: colors.onPrimaryAction)
                } else {
                    return TpsCategorySegment(id: idx, title: cluster, count: cnt, activeLight: SiapColors.brandTeal, activeDark: colors.secondary, activeFgDark: colors.onSecondary)
                }
            }
        }
    }

    private var clampedCategoryIndex: Int {
        let count = activeCategories.count
        guard count > 0 else { return 0 }
        return min(max(selectedCategoryIndex, 0), count - 1)
    }

    private var filteredGraha: [GrahaMonitorItem] {
        let filter = TpsFilterStatus(rawValue: clampedCategoryIndex) ?? .all
        return TpsFilterAndSort.filterAndSortGraha(rows: grahaRaw, filter: filter, query: searchQuery, sort: grahaSort)
    }

    private var filteredNpct: [NpctMonitorItem] {
        let filter = TpsFilterStatus(rawValue: clampedCategoryIndex) ?? .all
        return TpsFilterAndSort.filterAndSortNpct(rows: npctRaw, filter: filter, query: searchQuery, sort: npctSort)
    }

    private var activeTpslClusterName: String {
        let clusters = tpslClusters
        let idx = clampedCategoryIndex
        return idx < clusters.count ? clusters[idx] : "SEMUA"
    }

    private var filteredTpsl: [TpslMonitorItem] {
        TpsFilterAndSort.filterAndSortTpsl(rows: tpslRaw, clusterFilter: activeTpslClusterName, query: searchQuery, sort: tpslSort)
    }

    private var activeErrorMessage: String? {
        if let err = snapshot.errorMessage, !err.isEmpty {
            return err
        }
        switch source {
        case .graha:
            if snapshot.failedSources.contains("Graha") && grahaRaw.isEmpty {
                return "Gagal memuat antrian TPFT Graha Segara."
            }
        case .npct:
            if snapshot.failedSources.contains("NPCT") && npctRaw.isEmpty {
                return "Gagal memuat antrian Terminal NPCT1."
            }
        case .tpsl:
            if snapshot.failedSources.contains("TPSL") && tpslRaw.isEmpty {
                return "Gagal memuat antrian PKB TPS Lainnya."
            }
        }
        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // 1. Terminal Source Selector Strip (Graha | NPCT1 | TPSL)
            terminalSwitcherBar

            // 2. Top Controls Container (Matches Android TpsMonitoringHubScreen header stack)
            VStack(spacing: 5) {
                if showNpctImporterWarning {
                    npctImporterWarningBanner
                }

                ribbonBar

                if let errMsg = activeErrorMessage {
                    TpsErrorBannerView(message: errMsg, colors: colors) {
                        Task { await app.refreshTpsMonitoring(force: true) }
                    }
                }

                if isSearchVisible {
                    searchInputBar
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                TpsCategoryMenuBarView(
                    categories: activeCategories,
                    selectedIndex: clampedCategoryIndex,
                    colors: colors
                ) { idx in
                    selectedCategoryIndex = idx
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 6)
            .animation(.easeInOut(duration: 0.18), value: isSearchVisible)

            // 3. Scrollable Content Area with Native Pull-to-Refresh
            contentScrollArea
        }
        .background(colors.backdrop)
        .onChange(of: app.activeTpsSource) { _ in
            selectedCategoryIndex = 0
        }
        .task {
            await app.refreshTpsMonitoring(force: false)
        }
        .sheet(item: $lampiranTarget) { target in
            TpsDocumentLampiranSheet(item: target, colors: colors)
                .environmentObject(app)
                .preferredColorScheme(app.themeMode.preferredColorScheme)
        }
    }

    // MARK: - Subviews

    private var terminalSwitcherBar: some View {
        HStack(spacing: 6) {
            ForEach(TpsSource.allCases) { tab in
                let isActive = source == tab
                let count = terminalTotalCount(tab)
                let hasMine = terminalHasMyTask(tab)
                Button {
                    app.activeTpsSource = tab
                } label: {
                    HStack(spacing: 4) {
                        if hasMine {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9.5))
                                .foregroundStyle(isActive ? (colors.isDark ? Color(hex: 0x0B131D) : SiapColors.myTaskGold) : SiapColors.myTaskGold)
                        }
                        Text(tab.rawValue)
                            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                        if count > 0 {
                            Text("(\(count))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .opacity(isActive ? 0.9 : 0.7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7.5)
                    .background(isActive ? colors.primaryAction : colors.surfaceElevated)
                    .foregroundStyle(isActive ? colors.onPrimaryAction : colors.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(colors.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(colors.divider).frame(height: 0.75)
        }
    }

    private func terminalTotalCount(_ tab: TpsSource) -> Int {
        switch tab {
        case .graha: return grahaRaw.count
        case .npct: return npctRaw.count
        case .tpsl: return tpslRaw.count
        }
    }

    private func terminalHasMyTask(_ tab: TpsSource) -> Bool {
        switch tab {
        case .graha: return grahaRaw.contains(where: \.isMyTask)
        case .npct: return npctRaw.contains(where: \.isMyTask)
        case .tpsl: return tpslRaw.contains(where: \.isMyTask)
        }
    }

    private var npctImporterWarningBanner: some View {
        Button {
            Task { await app.refreshTpsMonitoring(force: true) }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x78350F))
                Text("Nama importir belum tersedia. Ketuk di sini untuk memuat ulang.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x78350F))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xFEF3C7))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var ribbonBar: some View {
        let clockText = snapshot.lastUpdated.isEmpty ? "Menunggu" : snapshot.lastUpdated
        switch source {
        case .graha:
            TpsCompactRibbonBarView(
                shortTitle: "TPFT Graha",
                shortUpdateText: clockText,
                totalCount: grahaRaw.count,
                count20: grahaCount20,
                count40: grahaCount40,
                extraBadgeText: nil,
                isSearchActive: isSearchVisible,
                sortLabel: grahaSort.label,
                sortOptions: GrahaSortOption.allCases,
                selectedSort: grahaSort,
                sortOptionLabel: { $0.label },
                showSortAction: !grahaRaw.isEmpty,
                isLoading: snapshot.isLoading,
                colors: colors,
                onToggleSearch: toggleSearch,
                onSelectSort: { grahaSort = $0 },
                onRefresh: { Task { await app.refreshTpsMonitoring(force: true) } }
            )
        case .npct:
            TpsCompactRibbonBarView(
                shortTitle: "Terminal NPCT1",
                shortUpdateText: clockText,
                totalCount: npctRaw.count,
                count20: npctCount20,
                count40: npctCount40,
                extraBadgeText: nil,
                isSearchActive: isSearchVisible,
                sortLabel: npctSort.label,
                sortOptions: NpctSortOption.allCases,
                selectedSort: npctSort,
                sortOptionLabel: { $0.label },
                showSortAction: !npctRaw.isEmpty,
                isLoading: snapshot.isLoading,
                colors: colors,
                onToggleSearch: toggleSearch,
                onSelectSort: { npctSort = $0 },
                onRefresh: { Task { await app.refreshTpsMonitoring(force: true) } }
            )
        case .tpsl:
            TpsCompactRibbonBarView(
                shortTitle: "TPS Lainnya",
                shortUpdateText: clockText,
                totalCount: tpslRaw.count,
                count20: nil,
                count40: nil,
                extraBadgeText: "Tot: \(tpslRaw.count) Dok",
                isSearchActive: isSearchVisible,
                sortLabel: tpslSort.label,
                sortOptions: TpslSortOption.allCases,
                selectedSort: tpslSort,
                sortOptionLabel: { $0.label },
                showSortAction: !tpslRaw.isEmpty,
                isLoading: snapshot.isLoading,
                colors: colors,
                onToggleSearch: toggleSearch,
                onSelectSort: { tpslSort = $0 },
                onRefresh: { Task { await app.refreshTpsMonitoring(force: true) } }
            )
        }
    }

    private func toggleSearch() {
        if isSearchVisible {
            searchQuery = ""
            isSearchExpanded = false
        } else {
            isSearchExpanded = true
        }
    }

    private var searchInputBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(colors.textHint)

            TextField(
                source == .tpsl
                    ? "Cari No. PIB, Importir, atau Lokasi TPS..."
                    : "Cari No. Kontainer, No. PIB, atau Importir...",
                text: $searchQuery
            )
            .font(.system(size: 13))
            .foregroundStyle(colors.textPrimary)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                if !searchQuery.isEmpty {
                    searchQuery = ""
                } else {
                    isSearchExpanded = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(colors.textHint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var contentScrollArea: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                switch source {
                case .graha:
                    if snapshot.isLoading && grahaRaw.isEmpty {
                        TpsLoadingStateView(message: "Memuat antrian TPFT Graha Segara...", colors: colors)
                    } else if filteredGraha.isEmpty {
                        TpsEmptyStateView(
                            message: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Tidak ada antrian di kategori ini saat ini."
                                : "Tidak ada kontainer cocok dengan pencarian.",
                            colors: colors
                        )
                    } else {
                        ForEach(filteredGraha) { item in
                            GrahaCardView(
                                item: item,
                                colors: colors,
                                onOpenPib: {
                                    let fallback = !item.noPib.isEmpty ? item.noPib : (!item.importir.isEmpty ? item.importir : item.noContainer)
                                    app.openPibFromTps(noPib: item.noPib, fallbackQuery: fallback)
                                },
                                onSearchBrowse: {
                                    let q = TpsRowKit.cleanServerField(item.noPib, fallback: item.noContainer)
                                    app.searchPibInBrowse(query: q, fromTps: true)
                                },
                                onOpenLampiran: {
                                    lampiranTarget = TpsLampiranTarget(
                                        source: "Graha",
                                        container: item.noContainer,
                                        pib: TpsRowKit.cleanServerField(item.noPib),
                                        importir: TpsRowKit.cleanServerField(item.importir),
                                        status: item.status,
                                        lokasi: item.lokasi,
                                        isMyTask: item.isMyTask
                                    )
                                }
                            )
                        }
                    }

                case .npct:
                    if snapshot.isLoading && npctRaw.isEmpty {
                        TpsLoadingStateView(message: "Memuat antrian terminal NPCT1...", colors: colors)
                    } else if filteredNpct.isEmpty {
                        TpsEmptyStateView(
                            message: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Tidak ada antrian di kategori NPCT1 ini."
                                : "Tidak ada kontainer cocok dengan pencarian.",
                            colors: colors
                        )
                    } else {
                        ForEach(filteredNpct) { item in
                            NpctCardView(
                                item: item,
                                colors: colors,
                                onOpenPib: {
                                    let fallback = !item.noPib.isEmpty ? item.noPib : (!item.importir.isEmpty ? item.importir : item.noContainer)
                                    app.openPibFromTps(noPib: item.noPib, fallbackQuery: fallback)
                                },
                                onSearchBrowse: {
                                    let q = TpsRowKit.cleanServerField(item.noPib, fallback: item.noContainer)
                                    app.searchPibInBrowse(query: q, fromTps: true)
                                },
                                onOpenLampiran: {
                                    lampiranTarget = TpsLampiranTarget(
                                        source: "NPCT1",
                                        container: item.noContainer,
                                        pib: TpsRowKit.cleanServerField(item.noPib),
                                        importir: TpsRowKit.cleanServerField(item.importir),
                                        status: item.status,
                                        lokasi: item.lokasi,
                                        isMyTask: item.isMyTask
                                    )
                                }
                            )
                        }
                    }

                case .tpsl:
                    if snapshot.isLoading && tpslRaw.isEmpty {
                        TpsLoadingStateView(message: "Memuat antrian PKB TPS Lainnya...", colors: colors)
                    } else if filteredTpsl.isEmpty {
                        TpsEmptyStateView(
                            message: searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Tidak ada antrian di klaster \(activeTpslClusterName) saat ini."
                                : "Tidak ada antrian cocok dengan pencarian.",
                            colors: colors
                        )
                    } else {
                        ForEach(filteredTpsl) { item in
                            TpslCardView(
                                item: item,
                                colors: colors,
                                onOpenPib: {
                                    let fallback = !item.noPib.isEmpty ? item.noPib : item.importir
                                    app.openPibFromTps(noPib: item.noPib, fallbackQuery: fallback)
                                },
                                onSearchBrowse: {
                                    let q = TpsRowKit.cleanServerField(item.noPib, fallback: item.importir)
                                    app.searchPibInBrowse(query: q, fromTps: true)
                                },
                                onOpenLampiran: {
                                    lampiranTarget = TpsLampiranTarget(
                                        source: "TPSL (\(item.cluster))",
                                        container: item.lokasi,
                                        pib: TpsRowKit.cleanServerField(item.noPib),
                                        importir: TpsRowKit.cleanServerField(item.importir),
                                        status: item.keputusan,
                                        lokasi: item.lokasi,
                                        isMyTask: item.isMyTask
                                    )
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 16)
        }
        .refreshable {
            await app.refreshTpsMonitoring(force: true)
        }
    }
}

// MARK: - TpsCompactRibbonBar (Exact Port of Android TpsCompactRibbonBar)

private struct TpsCompactRibbonBarView<SortOption: Hashable>: View {
    let shortTitle: String
    let shortUpdateText: String
    let totalCount: Int
    let count20: Int?
    let count40: Int?
    let extraBadgeText: String?
    let isSearchActive: Bool
    let sortLabel: String
    let sortOptions: [SortOption]
    let selectedSort: SortOption
    let sortOptionLabel: (SortOption) -> String
    let showSortAction: Bool
    let isLoading: Bool
    let colors: SiapColors
    let onToggleSearch: () -> Void
    let onSelectSort: (SortOption) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: Title • Clock  [Search] [Sort] [Refresh]
            HStack(spacing: 4) {
                HStack(spacing: 5) {
                    Text(shortTitle)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text("•")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))

                    Text(shortUpdateText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(colors.isDark ? colors.textSecondary : SiapColors.hintOnNavy)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    // Search Toggle Button (34x34)
                    Button(action: onToggleSearch) {
                        Image(systemName: isSearchActive ? "xmark" : "magnifyingglass")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(isSearchActive ? SiapColors.brandTeal : Color.white.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isSearchActive ? "Tutup Pencarian" : "Cari Data TPS")

                    // Sort Dropdown Button (34x34)
                    if showSortAction {
                        Menu {
                            ForEach(sortOptions, id: \.self) { opt in
                                Button {
                                    onSelectSort(opt)
                                } label: {
                                    if opt == selectedSort {
                                        Label(sortOptionLabel(opt), systemImage: "checkmark")
                                    } else {
                                        Text(sortOptionLabel(opt))
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.14))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .accessibilityLabel("Urutkan Data TPS")
                    }

                    // Refresh Button (34x34)
                    Button {
                        if !isLoading { onRefresh() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.75)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14.5, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                    .accessibilityLabel("Muat Ulang")
                }
            }

            // Row 2: Horizontal Metric Pills (20', 40', Tot, Urut)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if let c20 = count20, let c40 = count40 {
                        Text("20': \(c20)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(colors.isDark ? Color(hex: 0x38BDF8) : Color(hex: 0xE0F7FA))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(SiapColors.brandTeal.opacity(0.30))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text("40': \(c40)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(colors.isDark ? Color(hex: 0x93C5FD) : Color(hex: 0xE3F2FD))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color(hex: 0x1976D2).opacity(0.38))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Text("Tot: \(totalCount)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    } else {
                        Text(extraBadgeText ?? "Tot: \(totalCount) Dok")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.16))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if showSortAction {
                        Menu {
                            ForEach(sortOptions, id: \.self) { opt in
                                Button {
                                    onSelectSort(opt)
                                } label: {
                                    if opt == selectedSort {
                                        Label(sortOptionLabel(opt), systemImage: "checkmark")
                                    } else {
                                        Text(sortOptionLabel(opt))
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text("Urut: \(sortLabel)")
                                    .font(.system(size: 10.5, weight: .medium))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .foregroundStyle(Color.white.opacity(0.90))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(colors.isDark ? colors.surfaceElevated : SiapColors.brandNavy)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(colors.isDark ? colors.cardBorder : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - TpsCategoryMenuBar (Exact Port of Android TpsCategoryMenuBar)

private struct TpsCategoryMenuBarView: View {
    let categories: [TpsCategorySegment]
    let selectedIndex: Int
    let colors: SiapColors
    let onSelect: (Int) -> Void

    private var scrollable: Bool { categories.count > 4 }

    var body: some View {
        Group {
            if scrollable {
                ScrollView(.horizontal, showsIndicators: false) {
                    segmentRow
                }
            } else {
                segmentRow
            }
        }
        .padding(3)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var segmentRow: some View {
        HStack(spacing: 2) {
            ForEach(categories) { cat in
                let isSelected = cat.id == selectedIndex
                let activeBg = colors.isDark ? cat.activeDark : cat.activeLight
                let activeText = colors.isDark ? cat.activeFgDark : Color.white
                let inactiveCountColor = colors.isDark ? cat.activeDark : cat.activeLight

                Button {
                    onSelect(cat.id)
                } label: {
                    VStack(spacing: 1) {
                        Text(cat.title)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .semibold))
                            .foregroundStyle(isSelected ? activeText : colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("\(cat.count)")
                            .font(.system(size: 14.5, weight: .bold, design: .rounded))
                            .foregroundStyle(isSelected ? activeText : inactiveCountColor)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .frame(minWidth: scrollable ? 64 : 0, maxWidth: scrollable ? nil : .infinity)
                    .background(isSelected ? activeBg : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Shared RowDataKit Primitives (Exact Port of RowDataKitKt)

private struct TpsRowCapsLabel: View {
    let text: String
    let colors: SiapColors

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(colors.textHint)
            .lineLimit(1)
    }
}

private struct TpsLocationBox: View {
    let label: String
    let value: String
    let colors: SiapColors

    var body: some View {
        let display = TpsRowKit.cleanServerField(value, fallback: "-")
        let finalDisplay = display.isEmpty ? "-" : display
        let accent = TpsRowKit.locationAccentColor(finalDisplay, isDark: colors.isDark)
        let isShort = finalDisplay.count <= 6

        VStack(spacing: 2) {
            TpsRowCapsLabel(text: label, colors: colors)
            Text(finalDisplay)
                .font(.system(size: isShort ? 15.5 : 12, weight: .bold))
                .foregroundStyle(accent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
        .frame(minWidth: 54, maxWidth: 72)
    }
}

private struct TpsSizeChip: View {
    let size: String
    let colors: SiapColors

    var body: some View {
        let label = TpsRowKit.containerSizeLabel(size)
        if !label.isEmpty {
            let isLarge = label.hasPrefix("40") || label.hasPrefix("45")
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isLarge ? colors.surface : colors.textPrimary)
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(isLarge ? colors.textPrimary : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(colors.textSecondary, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .lineLimit(1)
        }
    }
}

private struct TpsRowStatusChip: View {
    let status: String
    let colors: SiapColors

    var body: some View {
        let short = TpsRowKit.shortStatusLabel(status)
        let st = colors.statusBadgeStyle(for: short)
        Text(short.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(st.bg)
            .foregroundStyle(st.fg)
            .overlay(
                Capsule().stroke(st.accent.opacity(colors.isDark ? 0.45 : 0.25), lineWidth: 1)
            )
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

private struct TpsRowSearchButton: View {
    let accessibilityText: String
    let colors: SiapColors
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(colors.onPrimaryContainer)
                .frame(width: 46, height: 46)
                .background(colors.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }
}

private struct TpsPibLine: View {
    let noPib: String
    let formattedDate: String
    let colors: SiapColors

    var body: some View {
        TpsFlowLayout(horizontalSpacing: 5, verticalSpacing: 0) {
            HStack(spacing: 5) {
                TpsRowCapsLabel(text: "PIB", colors: colors)
                Text(noPib.isEmpty ? "-" : noPib)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
            }
            if !formattedDate.isEmpty {
                Text("• \(formattedDate)")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TpsImportirLine: View {
    let importir: String
    let colors: SiapColors

    var body: some View {
        let cleaned = TpsRowKit.cleanServerField(importir, fallback: "")
        if !cleaned.isEmpty && cleaned != "-" {
            Text(cleaned)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(colors.textPrimary)
                .lineLimit(2)
                .padding(.top, 2)
        }
    }
}

private struct TpsFootField: View {
    let label: String
    let value: String
    let valueColor: Color
    let colors: SiapColors

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            TpsRowCapsLabel(text: label, colors: colors)
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(valueColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - TpsMonitorCardShell (Exact Port of Android TpsMonitorCardShell)

private struct TpsMonitorCardShell<Content: View>: View {
    let isMyTask: Bool
    let colors: SiapColors
    let onTapMyTask: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let cardBg: Color = {
            if isMyTask {
                return colors.isDark ? Color(hex: 0x1B2F23) : colors.myTaskBg
            }
            return colors.surface
        }()

        let cardBody = VStack(alignment: .leading, spacing: 0) {
            if isMyTask {
                HStack(spacing: 5) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(SiapColors.myTaskGold)
                    Text("DOKUMEN TUGAS SAYA · ketuk untuk membuka")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(colors.isDark ? Color(hex: 0xFDE68A) : Color(hex: 0x5C4600))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(SiapColors.myTaskGold.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.bottom, 6)
            }

            content()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isMyTask ? SiapColors.myTaskGold : (colors.isDark ? colors.divider : colors.cardBorder.opacity(0.75)),
                    lineWidth: isMyTask ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(
            color: colors.isDark ? .clear : Color.black.opacity(isMyTask ? 0.08 : 0.04),
            radius: isMyTask ? 4 : 2,
            y: 1
        )

        if isMyTask {
            Button(action: onTapMyTask) {
                cardBody
            }
            .buttonStyle(.plain)
        } else {
            cardBody
        }
    }
}

// MARK: - TpsContainerRow (Shared by GrahaCard & NpctCard)

private struct TpsContainerRow: View {
    let lokasi: String
    let noContainer: String
    let size: String
    let status: String
    let noPib: String
    let tglPib: String
    let importir: String
    let colors: SiapColors
    let onSearchBrowse: () -> Void

    var body: some View {
        let cleanPib = TpsRowKit.cleanServerField(noPib, fallback: "")
        let formattedDate = TpsRowKit.formatTpsDate(TpsRowKit.cleanServerField(tglPib, fallback: ""))
        let showSearch = !cleanPib.isEmpty && cleanPib != "N/A" && cleanPib != "-"

        HStack(alignment: .center, spacing: 0) {
            TpsLocationBox(label: "LOKASI", value: lokasi, colors: colors)

            Spacer().frame(width: 6)

            Rectangle()
                .fill(colors.divider)
                .frame(width: 1)
                .padding(.vertical, 2)

            Spacer().frame(width: 10)

            VStack(alignment: .leading, spacing: 2) {
                TpsFlowLayout(horizontalSpacing: 6, verticalSpacing: 2) {
                    Text(noContainer.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                    TpsSizeChip(size: size, colors: colors)
                    TpsRowStatusChip(status: status, colors: colors)
                }

                TpsPibLine(noPib: cleanPib, formattedDate: formattedDate, colors: colors)
                TpsImportirLine(importir: importir, colors: colors)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showSearch {
                Spacer().frame(width: 8)
                TpsRowSearchButton(
                    accessibilityText: "Cari PIB \(cleanPib) di Browse",
                    colors: colors,
                    action: onSearchBrowse
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - GrahaCard (Exact Port of Android GrahaCard)

private struct GrahaCardView: View {
    let item: GrahaMonitorItem
    let colors: SiapColors
    let onOpenPib: () -> Void
    let onSearchBrowse: () -> Void
    let onOpenLampiran: () -> Void

    var body: some View {
        TpsMonitorCardShell(isMyTask: item.isMyTask, colors: colors, onTapMyTask: onOpenPib) {
            TpsContainerRow(
                lokasi: item.lokasi,
                noContainer: item.noContainer,
                size: item.size,
                status: item.status,
                noPib: item.noPib,
                tglPib: item.tglPib,
                importir: item.importir,
                colors: colors,
                onSearchBrowse: onSearchBrowse
            )
        }
        .contextMenu {
            Button {
                onSearchBrowse()
            } label: {
                Label("Cari PIB di Browse", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                onOpenLampiran()
            } label: {
                Label("Lihat Lampiran PDF", systemImage: "paperclip")
            }
            if !item.noContainer.isEmpty && item.noContainer != "N/A" {
                Button {
                    UIPasteboard.general.string = item.noContainer
                } label: {
                    Label("Salin No. Kontainer", systemImage: "doc.on.doc")
                }
            }
            if !item.noPib.isEmpty && item.noPib != "N/A" {
                Button {
                    UIPasteboard.general.string = item.noPib
                } label: {
                    Label("Salin No. PIB", systemImage: "number")
                }
            }
        }
    }
}

// MARK: - NpctCard (Exact Port of Android NpctCard with NOTE / KET Footer)

private struct NpctCardView: View {
    let item: NpctMonitorItem
    let colors: SiapColors
    let onOpenPib: () -> Void
    let onSearchBrowse: () -> Void
    let onOpenLampiran: () -> Void

    var body: some View {
        let noteRaw = TpsRowKit.cleanServerField(item.note, fallback: "")
        let noteVal = (noteRaw.isEmpty || noteRaw == "-") ? nil : noteRaw

        let ketRaw = TpsRowKit.cleanServerField(item.keterangan, fallback: "")
        let ketPart = (ketRaw.isEmpty || ketRaw == "-") ? nil : ketRaw

        let respRaw = TpsRowKit.cleanServerField(item.respon, fallback: "")
        let respPart = (respRaw.isEmpty || respRaw == "-") ? nil : "Respon: \(respRaw)"

        let ketCombined = [ketPart, respPart].compactMap { $0 }.joined(separator: " · ")

        TpsMonitorCardShell(isMyTask: item.isMyTask, colors: colors, onTapMyTask: onOpenPib) {
            TpsContainerRow(
                lokasi: item.lokasi,
                noContainer: item.noContainer,
                size: item.size,
                status: item.status,
                noPib: item.noPib,
                tglPib: item.tglPib,
                importir: item.importir,
                colors: colors,
                onSearchBrowse: onSearchBrowse
            )

            if noteVal != nil || !ketCombined.isEmpty {
                Rectangle()
                    .fill(colors.divider)
                    .frame(height: 1)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                TpsFlowLayout(horizontalSpacing: 14, verticalSpacing: 2) {
                    if let noteVal {
                        TpsFootField(
                            label: "NOTE",
                            value: noteVal,
                            valueColor: TpsRowKit.locationAccentColor("NOTE", isDark: colors.isDark),
                            colors: colors
                        )
                    }
                    if !ketCombined.isEmpty {
                        TpsFootField(
                            label: "KET",
                            value: ketCombined,
                            valueColor: colors.textPrimary,
                            colors: colors
                        )
                    }
                }
            }
        }
        .contextMenu {
            Button {
                onSearchBrowse()
            } label: {
                Label("Cari PIB di Browse", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                onOpenLampiran()
            } label: {
                Label("Lihat Lampiran PDF", systemImage: "paperclip")
            }
            if !item.noContainer.isEmpty && item.noContainer != "N/A" {
                Button {
                    UIPasteboard.general.string = item.noContainer
                } label: {
                    Label("Salin No. Kontainer", systemImage: "doc.on.doc")
                }
            }
            if !item.noPib.isEmpty && item.noPib != "N/A" {
                Button {
                    UIPasteboard.general.string = item.noPib
                } label: {
                    Label("Salin No. PIB", systemImage: "number")
                }
            }
        }
    }
}

// MARK: - TpslCard (Exact Port of Android TpslCard with TPS Box & ANTRIAN)

private struct TpslCardView: View {
    let item: TpslMonitorItem
    let colors: SiapColors
    let onOpenPib: () -> Void
    let onSearchBrowse: () -> Void
    let onOpenLampiran: () -> Void

    var body: some View {
        let cleanPib = TpsRowKit.cleanServerField(item.noPib, fallback: "")
        let formattedDate = TpsRowKit.formatTpsDate(TpsRowKit.cleanServerField(item.tglPib, fallback: ""))
        let antrianClean = item.antrian.trimmingCharacters(in: .whitespacesAndNewlines)
        let showSearch = !cleanPib.isEmpty && cleanPib != "N/A" && cleanPib != "-"
        let antrianColor = colors.statusBadgeStyle(for: "PROSES").fg

        TpsMonitorCardShell(isMyTask: item.isMyTask, colors: colors, onTapMyTask: onOpenPib) {
            HStack(alignment: .center, spacing: 0) {
                TpsLocationBox(label: "TPS", value: item.lokasi, colors: colors)

                Spacer().frame(width: 6)

                Rectangle()
                    .fill(colors.divider)
                    .frame(width: 1)
                    .padding(.vertical, 2)

                Spacer().frame(width: 10)

                VStack(alignment: .leading, spacing: 2) {
                    TpsFlowLayout(horizontalSpacing: 8, verticalSpacing: 2) {
                        TpsPibLine(noPib: cleanPib, formattedDate: formattedDate, colors: colors)
                        if !antrianClean.isEmpty && antrianClean != "-" {
                            HStack(spacing: 4) {
                                TpsRowCapsLabel(text: "ANTRIAN", colors: colors)
                                Text(antrianClean)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(antrianColor)
                                    .lineLimit(1)
                            }
                        }
                    }

                    TpsImportirLine(importir: item.importir, colors: colors)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showSearch {
                    Spacer().frame(width: 8)
                    TpsRowSearchButton(
                        accessibilityText: "Cari PIB \(cleanPib) di Browse",
                        colors: colors,
                        action: onSearchBrowse
                    )
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .contextMenu {
            Button {
                onSearchBrowse()
            } label: {
                Label("Cari PIB di Browse", systemImage: "doc.text.magnifyingglass")
            }
            Button {
                onOpenLampiran()
            } label: {
                Label("Lihat Lampiran PDF", systemImage: "paperclip")
            }
            if !cleanPib.isEmpty && cleanPib != "N/A" {
                Button {
                    UIPasteboard.general.string = cleanPib
                } label: {
                    Label("Salin No. PIB", systemImage: "number")
                }
            }
        }
    }
}

// MARK: - TpsErrorBanner, TpsLoadingState & TpsEmptyState (Exact Android Ports)

private struct TpsErrorBannerView: View {
    let message: String
    let colors: SiapColors
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Gagal Memuat Data Real-time")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(colors.danger)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRetry) {
                Text("Coba Lagi")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(hex: 0xDC2626))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(hex: 0xDC2626).opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct TpsLoadingStateView: View {
    let message: String
    let colors: SiapColors
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(colors.isDark ? colors.primaryAction : SiapColors.brandNavy)
                .padding(.leading, 2)

            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(colors.divider)
                        .frame(width: 56, height: 48)

                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colors.divider)
                            .frame(height: 14)
                            .frame(maxWidth: 180)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colors.divider.opacity(0.75))
                            .frame(height: 12)
                            .frame(maxWidth: 140)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(colors.divider.opacity(0.6))
                            .frame(height: 11)
                            .frame(maxWidth: 210)
                    }
                    Spacer()
                }
                .padding(12)
                .background(colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(colors.cardBorder.opacity(0.7), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(pulse ? 0.55 : 0.95)
            }
        }
        .padding(.top, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

private struct TpsEmptyStateView: View {
    let message: String
    let colors: SiapColors

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(colors.isDark ? colors.primaryAction : SiapColors.brandNavy)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(colors.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(colors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.top, 36)
        .padding(.horizontal, 12)
    }
}
