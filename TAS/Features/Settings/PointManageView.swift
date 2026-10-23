import SwiftUI

/// 적립금 관리 — 웹 `PointManage`·안드로이드 `PointManageScreen`: 탭 내역 · 적립 · 설정 + 머리 '전체 잔액'.
/// 고객·예약은 고객 탭과 같은 뷰모델로 읽는다(상세 레이어 데이터까지 같이 만든다).
struct PointManageView: View {
    @Environment(SessionStore.self) private var session
    @State private var viewModel = CustomersViewModel()
    @State private var tab: Tab = .history
    @State private var route: DetailRoute?
    @State private var showSettings = false

    enum Tab: String, CaseIterable { case history = "내역", adjust = "적립", settings = "설정" }

    var body: some View {
        LoadableView(state: viewModel.state, loadingText: "적립금 불러오는 중…") { data in
            List {
                Section {
                    Picker("보기", selection: $tab) {
                        ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("전체 잔액", value: formatWon(data.customers.reduce(0) { $0 + ($1.points ?? 0) }))
                        .monospacedDigit()
                }
                switch tab {
                case .history: historySection(data)
                case .adjust: PointAdjustSection(customers: data.customers, onOpen: { route = .customer($0) },
                                                 onSave: save)
                case .settings: settingsSection
                }
            }
            .refreshable { await viewModel.load() }
        }
        .navigationTitle("적립금 관리")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .sheet(item: $route) { route in
            if let data = viewModel.detailData {
                DetailSheet(route: route, data: data, reload: { await viewModel.load() })
            }
        }
        .sheet(isPresented: $showSettings) { PointSettingsEditView().environment(session) }
    }

    private func save(_ updated: Customer) async throws {
        try await TASService().updateCustomer(updated)
        await viewModel.load()
    }

    // MARK: 내역 — 잔액 있는 고객만, 잔액 많은 순(같으면 이름), 고객마다 이력 최신부터

    @ViewBuilder private func historySection(_ data: CustomersViewModel.Data) -> some View {
        let holders = data.customers.filter { ($0.points ?? 0) > 0 }
            .sorted { ($0.points ?? 0, $1.name) > ($1.points ?? 0, $0.name) }
        Section {
            if holders.isEmpty {
                Text("등록된 데이터가 없습니다").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(holders) { customer in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(customer.name) { route = .customer(customer.id) }
                            .foregroundStyle(Color.linkText)
                            .accessibilityHint("고객 상세 열기")
                        if !customer.formattedTel.isEmpty { TelLink(customer: customer).font(.caption) }
                        Spacer()
                        Text(formatWon(customer.points ?? 0)).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                    .buttonStyle(.borderless)
                    ForEach((customer.pointHistories ?? []).reversed()) { entry in
                        if let id = entry.relatedReservationId, data.reservationsByCustomer[customer.id]?.contains(where: { $0.id == id }) == true {
                            Button { route = .reservation(id) } label: { PointHistoryRow(entry: entry) }
                                .buttonStyle(.borderless)
                                .accessibilityHint("예약 상세 열기")
                        } else {
                            PointHistoryRow(entry: entry)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("현재 적립금 보유 고객 전체 내역 · \(holders.count)명")
        } footer: {
            Text("현재 잔액이 남아있는 고객만 모아서 전체 적립/차감/충전 이력을 표시합니다.")
        }
    }

    // MARK: 설정 — 적립 방식·충전 기준(기존 편집 화면)

    private var settingsSection: some View {
        Section {
            Button("적립 방식·충전 기준 수정") { showSettings = true }
        } footer: {
            Text("결제 시 적립 퍼센트와 선불 충전 기준(기준금액 + 추가금)을 설정합니다.")
        }
    }
}

/// '적립' 탭 — 고객명·연락처 검색, 이름 순 전체 고객, 금액 + 적립/차감(차감은 잔액까지만).
private struct PointAdjustSection: View {
    let customers: [Customer]
    let onOpen: (Int) -> Void
    let onSave: (Customer) async throws -> Void

    @State private var query = ""
    /// 고객별 입력 — 글자로 들고 숫자만 9자리까지(안드로이드와 같다). 숫자 서식 칸은 입력을 늦게 반영해 버튼이 옛 값을 읽었다.
    @State private var amounts: [Int: String] = [:]
    @State private var savingId: Int?
    @State private var error: String?

    private var filtered: [Customer] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let digits = q.filter(\.isNumber)
        return customers.sortedByName().filter {
            q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || (!digits.isEmpty && $0.tel.contains(digits))
        }
    }

    var body: some View {
        Section {
            TextField("고객명 또는 연락처 검색", text: $query)
                .textInputAutocapitalization(.never)
            if let error { Text(error).font(.footnote).foregroundStyle(Color.dangerText) }
            if filtered.isEmpty {
                Text("등록된 데이터가 없습니다").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(filtered) { customer in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(customer.name) { onOpen(customer.id) }
                            .foregroundStyle(Color.linkText)
                            .accessibilityHint("고객 상세 열기")
                        Text(customer.formattedTel).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatWon(customer.points ?? 0)).font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                    HStack(spacing: 8) {
                        TextField("금액 입력", text: amountBinding(customer.id))
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(customer.name) 적립금 금액")
                        Button("적립") { apply(customer, add: true) }.buttonStyle(.action(.primary))
                        Button("차감") { apply(customer, add: false) }.buttonStyle(.action(.dangerOutline))
                    }
                    .disabled(savingId != nil)
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 4)
            }
        } header: {
            Text("고객 적립금 조정")
        }
    }

    private func amountBinding(_ id: Int) -> Binding<String> {
        Binding(get: { amounts[id] ?? "" }, set: { amounts[id] = String($0.filter(\.isNumber).prefix(9)) })
    }

    private func apply(_ customer: Customer, add: Bool) {
        guard let amount = amounts[customer.id].flatMap(Int.init), amount > 0 else { error = "금액을 입력해주세요."; return }
        guard let updated = PointAdjust.adjusted(customer, amount: amount, add: add,
                                                 now: ISO8601DateFormatter().string(from: Date()), id: UUID().uuidString) else {
            error = "차감할 적립금이 없습니다."; return
        }
        savingId = customer.id
        Task {
            do {
                try await onSave(updated)
                amounts[customer.id] = nil
                error = nil
            } catch {
                self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            savingId = nil
        }
    }
}
