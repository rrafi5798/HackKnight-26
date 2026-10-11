import SwiftUI

@main
struct BlindSpotApp: App {
    @StateObject private var store = MapStore()
    @AppStorage("blindspot.largeText") private var largeText = false
    @AppStorage("blindspot.highContrast") private var highContrast = false

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(store)
                .environment(\.dynamicTypeSize, largeText ? .xxxLarge : .large)
                .environment(\.colorSchemeContrast, highContrast ? .increased : .standard)
                .tint(Color(red: 0.08, green: 0.38, blue: 0.30))
                .task { store.refresh() }
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                NavigateView()
            }
            .tabItem {
                Label("Navigate", systemImage: "location.north.line")
            }

            NavigationStack {
                MySpacesView()
            }
            .tabItem {
                Label("My spaces", systemImage: "square.3.layers.3d")
            }

            NavigationStack {
                AccessSettingsView()
            }
            .tabItem {
                Label("Access", systemImage: "accessibility")
            }
        }
    }
}
