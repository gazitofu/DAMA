import SwiftUI

@main
struct DamaApp: App {
    var body: some Scene {
        WindowGroup("담아") {
            ReviewShell()
        }
        .defaultSize(width: 1_180, height: 760)
    }
}
