import SwiftUI

/// 예약 생성 폼 — 웹 `ReservationCreate` + `useReservationCreateForm` 이식(핵심 필드).
///
/// 필드 순서/규칙은 웹과 동일:
/// 고객(기존 검색 or 신규 이름+연락처) → 서비스(다중선택, 소요시간·가격 자동) →
/// 담당자 → 날짜 → 시작/종료 시간(종료는 소요시간으로 자동) → 가격(자동, 수정 가능) → 메모.
/// 저장 시 신규 고객이면 먼저 upsert 후 예약 생성(게스트=로컬/로그인=API 자동 분기).
/// (결제수단·포인트·담당자 가용성/중복 체크는 다음 단계.)
struct ReservationCreateView: View {
    let service: TASService
    let customers: [Customer]
    let assignees: [Assignee]            // 재직 중
    let catalog: [ServiceItem]
    let initialDate: Date
    let nextReservationId: Int
    let nextCustomerId: Int
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    // 고객
    @State private var customerId = 0          // 0 = 신규
    @State private var customerName = ""
    @State private var customerTel = ""
    @State private var showSuggestions = false
    // 서비스
    @State private var selectedServices: [String] = []
    // 폼
    @State private var date = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var isEndManual = false
    @State private var price = 0
    @State private var isPriceManual = false
    @State private var memo = ""
    // 상태
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, tel, price, memo }

    private static let seoul = TimeZone(identifier: "Asia/Seoul")!
    private var catalogMap: [String: ServiceItem] {
        Dictionary(catalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var totalDuration: Int { selectedServices.compactMap { catalogMap[$0]?.durationMinutes }.reduce(0, +) }
    private var totalPrice: Int { selectedServices.compactMap { catalogMap[$0]?.price }.reduce(0, +) }

    private var filteredCustomers: [Customer] {
        let q = customerName.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return customers.filter { $0.name.contains(q) || $0.tel.contains(q) }.prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                customerSection
                serviceSection
                priceSection
                assigneeSection
                dateTimeSection
                memoSection
                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("예약 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: setupInitial)
        }
    }

    // MARK: - 고객

    private var customerSection: some View {
        Section("고객") {
            TextField("고객명 검색 또는 신규 입력", text: $customerName)
                .focused($focusedField, equals: .name)
                .onChange(of: customerName) { _, _ in
                    if customerId != 0 { customerId = 0; customerTel = "" }  // 이름 재입력 → 신규 전환
                    showSuggestions = true
                    errorMessage = nil
                }
            if showSuggestions && !filteredCustomers.isEmpty {
                ForEach(filteredCustomers) { c in
                    Button {
                        selectCustomer(c)
                    } label: {
                        HStack {
                            Text(c.name)
                            Spacer()
                            Text(c.formattedTel).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            TextField("연락처", text: $customerTel)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .tel)
                .disabled(customerId != 0)   // 기존 고객이면 자동 채움(수정 불가)
        }
    }

    private func selectCustomer(_ c: Customer) {
        customerId = c.id
        customerName = c.name
        customerTel = c.tel
        showSuggestions = false
        focusedField = nil
        errorMessage = nil
    }

    // MARK: - 서비스

    /// 서비스 목록을 카테고리 헤더 + 항목으로 평탄화(웹 예약폼: 카테고리별 그룹).
    private enum ServiceRow: Identifiable {
        case header(String)
        case item(ServiceItem)
        var id: String {
            switch self {
            case .header(let c): return "h-\(c)"
            case .item(let s): return "s-\(s.name)"
            }
        }
    }

    private var serviceRows: [ServiceRow] {
        var seen = Set<String>()
        var categories: [String] = []
        for item in catalog where !seen.contains(item.category) {
            seen.insert(item.category); categories.append(item.category)
        }
        var rows: [ServiceRow] = []
        for category in categories {
            rows.append(.header(category))
            for item in catalog where item.category == category { rows.append(.item(item)) }
        }
        return rows
    }

    private var serviceSection: some View {
        Section {
            if catalog.isEmpty {
                Text("등록된 서비스가 없습니다. 설정에서 먼저 추가해주세요.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(serviceRows) { row in
                    switch row {
                    case .header(let category):
                        Text(category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    case .item(let item):
                        serviceItemRow(item)
                    }
                }
            }
        } header: {
            HStack {
                Text("서비스")
                Spacer()
                if !selectedServices.isEmpty {
                    Text("\(totalDuration)분 · \(formatWon(totalPrice))")
                        .font(.caption).textCase(nil).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 서비스 항목 행 — 웹처럼 체크박스(왼쪽) + 색 배경 칩 + "가격 · 소요시간"(오른쪽).
    private func serviceItemRow(_ item: ServiceItem) -> some View {
        let selected = selectedServices.contains(item.name)
        let color = ServiceColor.categoryColor(item.category)
        return Button { toggleService(item.name) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.accentColor : Color(.tertiaryLabel))
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.12))
                    .clipShape(Capsule())
                Spacer()
                Text("\(formatWon(item.price)) · \(item.durationMinutes)분")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleService(_ name: String) {
        if let i = selectedServices.firstIndex(of: name) { selectedServices.remove(at: i) }
        else { selectedServices.append(name) }
        // 소요시간 → 종료시간 자동(수동 편집 전), 가격 자동(수동 편집 전).
        isEndManual = false
        recomputeEndTime()
        if !isPriceManual { price = totalPrice }
        errorMessage = nil
    }

    // MARK: - 담당자

    @State private var assigneeId = 0

    @ViewBuilder private var assigneeSection: some View {
        if !assignees.isEmpty {
            Section("담당자") {
                Picker("담당자", selection: $assigneeId) {
                    ForEach(assignees) { a in Text(a.name).tag(a.id) }
                }
                .onChange(of: assigneeId) { _, _ in errorMessage = nil }
            }
        }
    }

    // MARK: - 날짜/시간

    private var dateTimeSection: some View {
        Section("일정") {
            DatePicker("날짜", selection: $date, displayedComponents: .date)
                .environment(\.timeZone, Self.seoul)
            DatePicker("시작", selection: $startTime, displayedComponents: .hourAndMinute)
                .environment(\.timeZone, Self.seoul)
                .onChange(of: startTime) { _, _ in if !isEndManual { recomputeEndTime() }; errorMessage = nil }
            DatePicker("종료", selection: $endTime, displayedComponents: .hourAndMinute)
                .environment(\.timeZone, Self.seoul)
                .onChange(of: endTime) { _, _ in isEndManual = true; errorMessage = nil }
        }
    }

    // MARK: - 가격 (웹: 서비스 바로 아래)

    private var priceSection: some View {
        Section("가격") {
            HStack {
                TextField("0", value: $price, format: .number)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .price)
                    .onChange(of: price) { _, _ in isPriceManual = true }
                Text("원").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 메모

    private var memoSection: some View {
        Section("메모") {
            TextField("메모", text: $memo, axis: .vertical)
                .focused($focusedField, equals: .memo)
                .lineLimit(1...3)
        }
    }

    // MARK: - 로직

    private func setupInitial() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.seoul
        date = initialDate
        // 시작 기본 10:00, 종료 +30분.
        let base = cal.date(bySettingHour: 10, minute: 0, second: 0, of: initialDate) ?? initialDate
        startTime = base
        endTime = cal.date(byAdding: .minute, value: 30, to: base) ?? base
        assigneeId = assignees.first?.id ?? 0
    }

    private func recomputeEndTime() {
        guard totalDuration > 0 else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.seoul
        endTime = cal.date(byAdding: .minute, value: totalDuration, to: startTime) ?? startTime
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.timeZone = Self.seoul
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// 웹 normalizeTel — 숫자만.
    private func normalizeTel(_ s: String) -> String { s.filter(\.isNumber) }
    private static let mobilePattern = "^01[016789]\\d{7,8}$"

    private func validate() -> String? {
        if !assignees.isEmpty && assigneeId == 0 { return "담당자를 선택해주세요." }
        if customerName.trimmingCharacters(in: .whitespaces).isEmpty { return "고객명을 입력해주세요." }
        let isNew = customerId == 0
        let tel = normalizeTel(customerTel)
        if isNew && customerTel.trimmingCharacters(in: .whitespaces).isEmpty { return "연락처를 입력해주세요." }
        if isNew && tel.range(of: Self.mobilePattern, options: .regularExpression) == nil {
            return "연락처 형식을 확인해주세요."
        }
        if selectedServices.isEmpty { return "서비스를 선택해주세요." }
        if timeString(startTime) >= timeString(endTime) { return "시작 시간은 종료 시간보다 앞서야 합니다." }
        return nil
    }

    private func save() async {
        if let err = validate() { errorMessage = err; return }
        isSaving = true
        defer { isSaving = false }
        do {
            var resolvedCustomerId = customerId
            if customerId == 0 {
                let newCustomer = Customer(
                    id: nextCustomerId,
                    name: customerName.trimmingCharacters(in: .whitespaces),
                    tel: normalizeTel(customerTel),
                    points: 0,
                    pointHistories: []
                )
                _ = try await service.upsertCustomer(newCustomer)
                resolvedCustomerId = newCustomer.id
            }
            let reservation = Reservation(
                id: nextReservationId,
                date: KST.dayKey.string(from: date),
                startTime: timeString(startTime),
                endTime: timeString(endTime),
                service: selectedServices.joined(separator: "+"),
                customerId: resolvedCustomerId,
                assigneeId: assigneeId == 0 ? nil : assigneeId,
                status: .active,
                price: price,
                memo: memo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : memo.trimmingCharacters(in: .whitespaces),
                channel: .phone
            )
            _ = try await service.createReservation(reservation)
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
