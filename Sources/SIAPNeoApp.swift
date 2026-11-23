import SwiftUI

@main
struct SIAPNeoApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                if appState.session != nil {
                    TabView {
                        HomeTabView()
                            .tabItem { Label("Beranda", systemImage: "house.fill") }
                        LorongTabView()
                            .tabItem { Label("Lorong", systemImage: "shippingbox.fill") }
                        BrowseTabView()
                            .tabItem { Label("Browse", systemImage: "doc.text.magnifyingglass") }
                        TpsTabView()
                            .tabItem { Label("TPS", systemImage: "ferry.fill") }
                        UserTabView()
                            .tabItem { Label("Akun", systemImage: "person.crop.circle.fill") }
                    }
                    .tint(SiapPalette.navy)
                } else {
                    LoginView()
                }

                if let msg = appState.toastMessage {
                    Text(msg)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(SiapPalette.navyDark.opacity(0.94))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 4)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .environmentObject(appState)
            .animation(.easeInOut(duration: 0.2), value: appState.toastMessage)
        }
    }
}
