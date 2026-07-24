import SwiftUI
import Observation

@MainActor
@Observable
final class NoticesViewModel {
    var state: Loadable<[StoreNotice]> = .idle
    var actionError: String?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    /// 고정 우선 → 최신순.
    var sorted: [StoreNotice] {
        (state.value ?? []).sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
    }

    /// 현재 고정된 공지 수(고정 한도 검사용).
    var pinnedCount: Int { (state.value ?? []).filter(\.pinned).count }

    func load() async {
        state = .loading
        do {
            state = .loaded(try await service.fetchNotices().notices)
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    func save(_ notice: StoreNotice, isNew: Bool) async -> Bool {
        do {
            if isNew { _ = try await service.createNotice(notice) }
            else { _ = try await service.updateNotice(notice) }
            await load()
            actionError = nil
            return true
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func delete(_ id: String) async {
        do {
            try await service.deleteNotice(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// 공지 관리 — 웹 설정 > `NoticeManageSection` 이식. 설정에서 push.
struct NoticesView: View {
    @State private var viewModel = NoticesViewModel()
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case create
        case edit(StoreNotice)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let n): return "edit-\(n.id)"
            }
        }
    }

    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "공지 불러오는 중…") { _ in
            if viewModel.sorted.isEmpty {
                ContentUnavailableView("공지 없음", systemImage: "megaphone", description: Text("우측 상단 + 로 공지를 추가하세요."))
            } else {
                List {
                    ForEach(viewModel.sorted) { notice in
                        Button {
                            activeSheet = .edit(notice)
                        } label: {
                            NoticeRow(notice: notice)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("삭제", role: .destructive) {
                                Task { await viewModel.delete(notice.id) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("공지")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = .create
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.state.value == nil)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                NoticeFormView(pinnedCount: viewModel.pinnedCount) { await viewModel.save($0, isNew: true) }
            case .edit(let notice):
                NoticeFormView(editing: notice, pinnedCount: viewModel.pinnedCount) { await viewModel.save($0, isNew: false) }
            }
        }
        .task { await viewModel.load() }
    }
}

private struct NoticeRow: View {
    let notice: StoreNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if notice.pinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.orange)
                }
                Text(notice.category.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(notice.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer()
                if !notice.visible {
                    Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !notice.body.isEmpty {
                Text(notice.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack { NoticesView() }
}
