import SwiftUI

@main
struct ReceiptAnalyzerApp: App {
    @StateObject private var store = ReceiptStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
