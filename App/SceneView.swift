import SwiftUI
import WebKit

/// Состояние сцены на главном экране — какую «серию» мультфильма показать.
enum StovePhase: String {
    case nokey, off, connecting, on, error
}

/// Сцена «изба, печь, ушат и Вовка» с анимацией.
///
/// Рисунок и движение — App/Scene/scene.html: SVG + CSS-анимации, собранные
/// скриптом scripts/pechka (`make scene`) из того же кода, что рисует холст
/// Design. WKWebView выбран намеренно: один источник рисунка для дизайна и
/// приложения, а покадровую «перекладку» CSS показывает без единой строки
/// Swift. Сцена декоративная: статус дублируется текстом ниже, поэтому для
/// VoiceOver она скрыта. «Уменьшение движения» WebKit передаёт в CSS сам
/// (prefers-reduced-motion) — остаются итоговые позы.
///
/// Смена фазы с «connecting» на «on» заново запускает анимацию «ПЫХ!»:
/// слои фазы «on» появляются из display:none, и CSS проигрывает их с начала.
struct SceneView: UIViewRepresentable {
    let phase: StovePhase

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(Pk.brevno)
        view.scrollView.backgroundColor = UIColor(Pk.brevno)
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isUserInteractionEnabled = false
        view.navigationDelegate = context.coordinator

        context.coordinator.phase = phase
        if let url = Bundle.main.url(forResource: "scene", withExtension: "html") {
            // Начальная фаза — в адресе, чтобы не мелькала «спящая» сцена.
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "phase", value: phase.rawValue)]
            view.loadFileURL(components?.url ?? url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.phase != phase else { return }
        context.coordinator.phase = phase
        if context.coordinator.loaded {
            view.evaluateJavaScript("setPhase('\(phase.rawValue)')")
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var phase: StovePhase = .off
        var loaded = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            // Фаза могла смениться, пока страница грузилась.
            webView.evaluateJavaScript("setPhase('\(phase.rawValue)')")
        }
    }
}
