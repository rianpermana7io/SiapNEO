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
                            .tabItem { Label("Tugas", systemImage: "list.clipboard.fill") }
                        PendokTabView()
                            .tabItem { Label("Pendok", systemImage: "folder.fill") }
                        TpsTabView()
                            .tabItem { Label("TPS", systemImage: "ferry.fill") }
                        UserTabView()
                            .tabItem { Label("Akun", systemImage: "person.crop.circle.fill") }
                    }
                } else {
                    LoginView()
                }

                if let msg = appState.toastMessage {
                    Text(msg)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.82))
                        .cornerRadius(12)
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
