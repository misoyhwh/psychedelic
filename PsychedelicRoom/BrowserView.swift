import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKUIDelegate {
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}

@Observable
@MainActor
class WebViewStore {
    let webView: WKWebView
    var canGoBack: Bool = false
    var canGoForward: Bool = false

    private var backObservation: NSKeyValueObservation?
    private var forwardObservation: NSKeyValueObservation?

    init() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        self.webView = wv

        backObservation = wv.observe(\.canGoBack, options: .new) { [weak self] _, change in
            Task { @MainActor in self?.canGoBack = change.newValue ?? false }
        }
        forwardObservation = wv.observe(\.canGoForward, options: .new) { [weak self] _, change in
            Task { @MainActor in self?.canGoForward = change.newValue ?? false }
        }
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
}

struct BrowserWindowView: View {
    @State private var urlText: String = "https://www.youtube.com"
    @State private var store = WebViewStore()
    @State private var hasLoaded = false
    @State private var toolbarVisible = true

    var body: some View {
        VStack(spacing: 0) {
            if toolbarVisible {
                HStack(spacing: 8) {
                    Button {
                        store.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!store.canGoBack)
                    .buttonStyle(.bordered)

                    Button {
                        store.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!store.canGoForward)
                    .buttonStyle(.bordered)

                    TextField("URL", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { navigateTo(urlText) }
                        .frame(maxWidth: 350)

                    Button("Go") {
                        navigateTo(urlText)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        withAnimation { toolbarVisible = false }
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
            } else {
                HStack {
                    Spacer()
                    Button {
                        withAnimation { toolbarVisible = true }
                    } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(.bordered)
                    .padding(8)
                }
            }

            BrowserWebView(webView: store.webView)
                .onAppear {
                    if !hasLoaded {
                        hasLoaded = true
                        if let url = URL(string: urlText) {
                            store.load(url)
                        }
                    }
                }
        }
    }

    private func navigateTo(_ text: String) {
        var urlString = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        if let url = URL(string: urlString) {
            store.load(url)
        }
    }
}
