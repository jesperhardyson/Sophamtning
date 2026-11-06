import SafariServices
import SophamtningDesign
import SophamtningKit
import SwiftUI
import UIKit

/// Safari-vyn i appen. Sidan läses inte in i någon egen `WKWebView`, så appen ser aldrig innehållet.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    /// Visar länken i ett ark i helskärm. **Klar** stänger arket och lämnar vyn som den var.
    func inAppBrowser(item: Binding<WebLink?>) -> some View {
        fullScreenCover(item: item) { link in
            SafariView(url: link.url)
                .tint(Color.Theme.primary)
                .ignoresSafeArea()
        }
    }
}
