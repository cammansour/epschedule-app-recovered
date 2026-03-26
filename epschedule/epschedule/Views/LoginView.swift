
import SwiftUI
import WebKit

struct LoginView: View {
    @StateObject private var api = EPScheduleAPI.shared
    @State private var showWebView = false
    @Environment(\.colorScheme) var colorScheme
    
    private var iconImage: Image? {
        if let uiImage = UIImage(named: "icon") {
            return Image(uiImage: uiImage)
        }
        if let iconURL = Bundle.main.url(forResource: "icon@3x", withExtension: "png"),
           let uiImage = UIImage(contentsOfFile: iconURL.path) {
            return Image(uiImage: uiImage)
        }
        if let iconURL = Bundle.main.url(forResource: "icon", withExtension: "png"),
           let uiImage = UIImage(contentsOfFile: iconURL.path) {
            return Image(uiImage: uiImage)
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                VStack(spacing: 32) {
                    if let icon = iconImage {
                        icon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                            .padding(.top, 80)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .frame(width: 120, height: 120)
                            .overlay(
                                Text("EPS")
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundColor(.gray)
                            )
                            .padding(.top, 80)
                    }
                    
                    VStack(spacing: 12) {
                        Text("Welcome to EPSchedule")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(Color.primary)
                        
                        Text("Schedules and events, all in one.")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundColor(Color.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                }
                
                Spacer()
                
                SignInWithMicrosoftButton {
                    showWebView = true
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 50)
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showWebView) {
            OAuthWebViewController(isPresented: $showWebView)
        }
        .onAppear {
            _ = api.hasAuthenticationCookies()
        }
        .onChange(of: api.isAuthenticated) { isAuth in
            if isAuth {
                showWebView = false
            }
        }
    }
}

struct SignInWithMicrosoftButton: View {
    let action: () -> Void
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 20))
                
                Text("Sign in with Microsoft")
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(colorScheme == .dark ? Color.white : Color.black)
            .cornerRadius(12)
        }
    }
}

struct OAuthWebViewController: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let webVC = OAuthWebViewControllerImpl()
        webVC.onDismiss = {
            isPresented = false
        }
        webVC.onAuthenticated = {
            isPresented = false
        }
        
        let navController = UINavigationController(rootViewController: webVC)
        return navController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

class OAuthWebViewControllerImpl: UIViewController, WKNavigationDelegate, WKUIDelegate {
    var webView: WKWebView!
    var popupWebView: WKWebView?
    var onDismiss: (() -> Void)?
    var onAuthenticated: (() -> Void)?
    private var authCheckTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Sign In"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissTapped)
        )
        
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        
        view.addSubview(webView)
        
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        cookieStore.add(self)
        
        if let url = URL(string: "https://www.epschedule.com") {
            webView.load(URLRequest(url: url))
        }
        
        authCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkAuthentication()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        authCheckTimer?.invalidate()
    }
    
    @objc func dismissTapped() {
        authCheckTimer?.invalidate()
        onDismiss?()
    }
    
    private func checkAuthentication() {
        syncCookies { [weak self] in
            let hasAuth = EPScheduleAPI.shared.hasAuthenticationCookies()
            print("🔐 Authentication check: \(hasAuth)")
            
            if hasAuth {
                if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: "https://www.epschedule.com")!) {
                    print("✅ Authenticated! Cookies available:")
                    for cookie in cookies {
                        print("   - \(cookie.name): \(cookie.value.prefix(30))... (domain: \(cookie.domain))")
                    }
                }
                
                self?.authCheckTimer?.invalidate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.onAuthenticated?()
                }
            }
        }
    }
    
    private func syncCookies(completion: @escaping () -> Void) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            print("🍪 Syncing \(cookies.count) cookies from WebView:")
            for cookie in cookies {
                print("   - \(cookie.name) (domain: \(cookie.domain))")
                HTTPCookieStorage.shared.setCookie(cookie)
            }
            
            if let popup = self.popupWebView {
                popup.configuration.websiteDataStore.httpCookieStore.getAllCookies { popupCookies in
                    print("🍪 Syncing \(popupCookies.count) cookies from popup WebView:")
                    for cookie in popupCookies {
                        print("   - \(cookie.name) (domain: \(cookie.domain))")
                        HTTPCookieStorage.shared.setCookie(cookie)
                    }
                    DispatchQueue.main.async {
                        completion()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("Page loaded: \(webView.url?.absoluteString ?? "unknown")")
        syncCookies { [weak self] in
            self?.checkAuthentication()
        }
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        print("Redirect to: \(webView.url?.absoluteString ?? "unknown")")
        syncCookies {}
    }
    
    
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        print("Creating popup for: \(navigationAction.request.url?.absoluteString ?? "unknown")")
        
        let popupWebView = WKWebView(frame: view.bounds, configuration: configuration)
        popupWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self
        
        let popupVC = UIViewController()
        popupVC.view.addSubview(popupWebView)
        popupVC.title = "Microsoft Sign In"
        popupVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(closePopup)
        )
        
        self.popupWebView = popupWebView
        navigationController?.pushViewController(popupVC, animated: true)
        
        return popupWebView
    }
    
    @objc func closePopup() {
        print("🔐 Popup closed manually")
        syncCookies { [weak self] in
            self?.navigationController?.popViewController(animated: true)
            self?.popupWebView = nil
            self?.checkAuthentication()
        }
    }
    
    func webViewDidClose(_ webView: WKWebView) {
        print("🔐 Popup closed by JavaScript")
        if webView == popupWebView {
            popupWebView = nil
            syncCookies { [weak self] in
                self?.navigationController?.popViewController(animated: true)
                self?.checkAuthentication()
            }
        }
    }
    
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })
        present(alert, animated: true)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })
        present(alert, animated: true)
    }
}

extension OAuthWebViewControllerImpl: WKHTTPCookieStoreObserver {
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        syncCookies { [weak self] in
            self?.checkAuthentication()
        }
    }
}
