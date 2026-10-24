import SwiftUI
import WebKit

struct EmbedWebView: UIViewRepresentable {
    let url: URL
    let cleanerEnabled: Bool
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.configureAndLoad(url, in: webView, cleanerEnabled: cleanerEnabled)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.configureAndLoad(url, in: webView, cleanerEnabled: cleanerEnabled)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private static let contentRuleListIdentifier = "CineNexPlaybackCleaner-v1"

        private let onFailure: () -> Void
        private var lastConfigurationKey: String?

        init(onFailure: @escaping () -> Void) {
            self.onFailure = onFailure
        }

        func configureAndLoad(_ url: URL, in webView: WKWebView, cleanerEnabled: Bool) {
            let key = "\(url.absoluteString)|\(cleanerEnabled)"
            guard lastConfigurationKey != key else { return }
            lastConfigurationKey = key

            guard cleanerEnabled else {
                webView.configuration.userContentController.removeAllContentRuleLists()
                load(url, in: webView, configurationKey: key)
                return
            }

            do {
                let ruleJSON = try PlaybackCleanerPolicy.contentBlockerJSON()
                guard let store = WKContentRuleListStore.default() else {
                    load(url, in: webView, configurationKey: key)
                    return
                }
                store.lookUpContentRuleList(forIdentifier: Self.contentRuleListIdentifier) { [weak self, weak webView] cachedRuleList, _ in
                    guard let self, let webView, self.lastConfigurationKey == key else { return }
                    if let cachedRuleList {
                        self.install(cachedRuleList, in: webView, url: url, configurationKey: key)
                        return
                    }

                    store.compileContentRuleList(
                        forIdentifier: Self.contentRuleListIdentifier,
                        encodedContentRuleList: ruleJSON
                    ) { [weak self, weak webView] compiledRuleList, _ in
                        DispatchQueue.main.async {
                            guard let self, let webView, self.lastConfigurationKey == key else { return }
                            if let compiledRuleList {
                                self.install(compiledRuleList, in: webView, url: url, configurationKey: key)
                            } else {
                                self.load(url, in: webView, configurationKey: key)
                            }
                        }
                    }
                }
            } catch {
                load(url, in: webView, configurationKey: key)
            }
        }

        private func install(_ ruleList: WKContentRuleList, in webView: WKWebView, url: URL, configurationKey: String) {
            guard lastConfigurationKey == configurationKey else { return }
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            controller.add(ruleList)
            load(url, in: webView, configurationKey: configurationKey)
        }

        private func load(_ url: URL, in webView: WKWebView, configurationKey: String) {
            guard lastConfigurationKey == configurationKey else { return }
            webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 20))
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onFailure()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            onFailure()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  PlaybackCleanerPolicy.shouldAllowNavigation(to: url, cleanerEnabled: cleanerEnabledForCurrentPage) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private var cleanerEnabledForCurrentPage: Bool {
            guard let lastConfigurationKey,
                  let separator = lastConfigurationKey.lastIndex(of: "|") else { return false }
            return lastConfigurationKey[lastConfigurationKey.index(after: separator)...] == "true"
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }
    }
}
