import SwiftUI
import Observation

/// 온라인 예약 요청함 — 웹 `BookingRequestNotification`(헤더 벨) 이식.
///
/// 고객이 공개 예약 페이지에서 보낸 **신규 신청 / 변경 요청 / 취소 요청**은 즉시 반영되지 않고
/// `pendingAction`으로 대기한다. 오너가 수락해야 예약에 반영되므로, 앱에도 이 목록이 없으면
/// 앱만 쓰는 오너는 고객 요청을 영영 보지 못한다.
@MainActor
@Observable
final class BookingRequestsViewModel {
    var state: Loadable<[BookingRequest]> = .idle
    /// 처리 중인 항목 id — 연속 탭으로 같은 요청을 두 번 보내지 않게 막는다.
    var busyId: String?
    var actionError: String?

    private let service: TASService

    init(service: TASService = TASService()) {
        self.service = service
    }

    var requests: [BookingRequest] { state.value ?? [] }
    var pendingCount: Int { requests.count }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await service.fetchBookingRequests())
        } catch {
            state = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// 수락/거절. 예약이 실제로 바뀌었으면 true(캘린더 새로고침이 필요하다는 뜻).
    ///
    /// 변경·취소 요청을 **거절**하면 요청만 폐기되고 예약은 그대로라 새로고침할 것이 없다.
    /// 신규 신청은 수락(→예약)·거절(→취소) 모두 예약 상태가 바뀐다.
    func decide(_ request: BookingRequest, _ decision: BookingDecision) async -> Bool {
        guard busyId == nil else { return false }
        busyId = request.id
        defer { busyId = nil }
        do {
            try await service.decideBookingRequest(id: request.id, decision: decision)
            actionError = nil
            await load()
            return decision == .approve || request.kind == .new
        } catch {
            actionError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}

/// 캘린더 툴바의 요청함 진입 버튼(대기 건수 배지). 웹 헤더 벨과 같은 자리·같은 역할.
/// 온라인예약을 쓰는 매장에선 대기 건이 없어도 상시 노출한다(웹과 동일 — 진입점을 숨기지 않는다).
struct BookingRequestsButton: View {
    /// 요청 수락으로 예약이 바뀌었을 때 캘린더를 다시 읽는다.
    let onApplied: () async -> Void

    @State private var viewModel = BookingRequestsViewModel()
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "tray")
                .overlay(alignment: .topTrailing) {
                    if viewModel.pendingCount > 0 {
                        CountBadge(count: viewModel.pendingCount).offset(x: 9, y: -9)
                    }
                }
        }
        .accessibilityLabel(viewModel.pendingCount > 0
            ? "예약 요청 \(viewModel.pendingCount)건"
            : "예약 요청")
        .sheet(isPresented: $isPresented) {
            BookingRequestsView(viewModel: viewModel, onApplied: onApplied)
        }
        .task { await viewModel.load() }
    }
}

/// 요청함 시트 — 대기 중인 신청·변경·취소를 한 목록에 놓고 바로 수락/거절한다.
struct BookingRequestsView: View {
    let viewModel: BookingRequestsViewModel
    let onApplied: () async -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LoadableView(state: viewModel.state, loadingText: "예약 요청 불러오는 중…") { requests in
                if requests.isEmpty {
                    ContentUnavailableView(
                        "대기 중인 요청 없음",
                        systemImage: "checkmark.circle",
                        description: Text("고객이 보낸 예약 신청·변경·취소 요청이 여기에 모입니다.")
                    )
                } else {
                    List(requests) { request in
                        BookingRequestRow(
                            request: request,
                            isBusy: viewModel.busyId != nil,
                            onDecide: { decision in
                                Task {
                                    if await viewModel.decide(request, decision) { await onApplied() }
                                }
                            }
                        )
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await viewModel.load() }
                }
            }
            .navigationTitle("예약 요청")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
            }
            .alert("처리하지 못했습니다", isPresented: errorBinding) {
                Button("확인", role: .cancel) { viewModel.actionError = nil }
            } message: {
                Text(viewModel.actionError ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.actionError != nil }, set: { if !$0 { viewModel.actionError = nil } })
    }
}

private struct BookingRequestRow: View {
    let request: BookingRequest
    let isBusy: Bool
    let onDecide: (BookingDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(request.customerName.isEmpty ? "고객" : request.customerName)
                    .font(.subheadline.weight(.semibold))
                BookingRequestKindBadge(kind: request.kind)
                Spacer()
                if let assigneeName = request.assigneeName, !assigneeName.isEmpty {
                    Text(assigneeName).font(.caption2).foregroundStyle(.secondary)
                }
            }

            // 신규 신청은 그 자체가 신청 내용이고, 변경/취소는 '현재 예약'이 무엇인지가 판단 근거다.
            slotLine(label: request.kind == .new ? "신청" : "현재", slot: request.current, isAccent: false)
            if request.kind == .change, let requestedChange = request.requestedChange {
                slotLine(label: "변경", slot: requestedChange, isAccent: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("거절") { onDecide(.reject) }
                    .buttonStyle(.bordered)
                    .tint(.red)
                Button("수락") { onDecide(.approve) }
                    .buttonStyle(.borderedProminent)
            }
            .font(.subheadline)
            .disabled(isBusy)
        }
        .padding(.vertical, 4)
    }

    private func slotLine(label: String, slot: BookingRequestSlot, isAccent: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isAccent ? Color.accentColor : Color.secondary)
            Text("\(monthDay(slot.date)) \(slot.startTime)~\(slot.endTime)")
                .font(.caption)
            Text(slot.serviceSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// "2026-08-10" → "8/10" (웹 `formatMd`).
    private func monthDay(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)/\(day)"
    }
}

/// 요청 종류 배지 — 웹 `LabelBadge`의 tone(warning/purple/danger)에 대응.
private struct BookingRequestKindBadge: View {
    let kind: BookingRequestKind

    var body: some View {
        Text(kind.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch kind {
        case .new: return Color(hex: "A88417") ?? .orange
        case .change: return Color(hex: "6526D9") ?? .purple
        case .cancel: return Color(hex: "EA4335") ?? .red
        }
    }
}

/// 대기 건수 배지(툴바 아이콘 위). 9건을 넘으면 웹과 같이 "9+".
private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 14, minHeight: 14)
            .background(Color.red, in: Capsule())
    }
}
