import SafariServices
import SophamtningKit
import SwiftUI
import UIKit

/// Safari-vyn i appen. Sidan läses inte in i någon egen `WKWebView`, så appen ser aldrig innehållet.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Visar länken i ett ark i helskärm. Stäng-knappen i webbvyn (X i iOS 26, annars **Klar**) stänger arket och lämnar vyn som den var.
    func inAppBrowser(item: Binding<WebLink?>) -> some View {
        fullScreenCover(item: item) { link in
            SafariView(url: link.url)
                .ignoresSafeArea()
        }
    }
}
