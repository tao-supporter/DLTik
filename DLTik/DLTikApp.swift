import SwiftUI

@main
struct DLTikApp: App {
    @StateObject private var downloader = Downloader()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloader)
                .preferredColorScheme(.dark)
        }
    }
}
