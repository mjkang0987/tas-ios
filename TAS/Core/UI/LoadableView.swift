import SwiftUI

/// Loadable 상태(idle/loading/failed/loaded)의 공통 분기 뷰.
/// 각 화면이 반복하던 switch 보일러플레이트를 한 곳으로.
struct LoadableView<Value, Content: View>: View {
    let state: Loadable<Value>
    var loadingText: String = "불러오는 중…"
    @ViewBuilder var content: (Value) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView(loadingText)
        case .failed(let message):
            ContentUnavailableView(
                "불러오지 못했습니다",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .loaded(let value):
            content(value)
        }
    }
}
