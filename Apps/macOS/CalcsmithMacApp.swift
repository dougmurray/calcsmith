import CalcsmithUI
import SwiftUI

@main
struct CalcsmithMacApp: App {
    var body: some Scene {
        WindowGroup("Calcsmith") {
            CalcsmithRootView()
                .frame(minWidth: 680, minHeight: 640)
        }
        .defaultSize(width: 760, height: 700)
        .windowToolbarStyle(.unified(showsTitle: false))
    }
}
