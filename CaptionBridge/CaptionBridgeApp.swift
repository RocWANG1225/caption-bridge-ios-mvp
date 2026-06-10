import SwiftUI

@main
struct CaptionBridgeApp: App {
    @StateObject private var captionSession = CaptionSession()
    @StateObject private var settings = CaptionSettings()

    var body: some Scene {
        WindowGroup {
            CaptionScreen()
                .environmentObject(captionSession)
                .environmentObject(settings)
                .onOpenURL { url in
                    if url.host == "start" || url.absoluteString == "captionbridge://start" {
                        captionSession.requestAutoStart()
                    }
                }
                .onContinueUserActivity("StartCaptionIntent") { _ in
                    captionSession.requestAutoStart()
                }
        }
    }
}
