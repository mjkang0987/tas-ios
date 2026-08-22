import SwiftUI

/// 예약 생성 폼 — 웹 `ReservationCreate` + `useReservationCreateForm` 이식(핵심 필드).
///
/// 필드 순서/규칙은 웹과 동일:
/// 고객(기존 검색 or 신규 이름+연락처) → 서비스(다중선택, 소요시간·가격 자동) →
/// 담당자 → 날짜 → 시작/종료 시간(종료는 소요시간으로 자동) → 가격(자동, 수정 가능) → 메모.
/// 저장 시 신규 고객이면 먼저 upsert 후 예약 생성(게스트=로컬/로그인=API 자동 분기).
/// 담당자 가용성(중복 예약)은 `ReservationOverlap`로 겹침을 감지해 경고·확인한다.
/// 신규 예약은 선택적으로 "결제완료로 등록"(단일 결제수단 + 적립률 자동 적립)할 수 있다.
struct ReservationCreateView: View {
    let service: TASService
    let customers: [Customer]
    let assignees: [Assignee]            // 재직 중
    let catalog: [ServiceItem]
    /// 서비스명 → hex(웹 `SERVICE_COLOR_MAP`). 시술 칩 색에 쓴다.
    /// 기본값을 두지 않는다 — 빠뜨리면 칩이 전부 폴백 회색으로 조용히 그려진다.
    let serviceColorMap: [String: String]
    /// 담당자 겹침(중복 예약) 체크용 — 전체 예약(날짜·담당자로 내부 필터).
    let existingReservations: [Reservation]
    /// 매장 적립률(%). 결제완료로 등록 시 자동 적립에 사용. 0이면 적립 없음.
    var pointRate: Int = 0
    let initialDate: Date
    let nextReservationId: Int
    let nextCustomerId: Int
    /// 편집 대상 예약. nil이면 신규 생성, 있으면 해당 예약을 수정(PUT).
    var editing: Reservation? = nil
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
    // 프로그램적 변경이 onChange를 통해 "수동 편집"으로 오인되는 것 방지(값이 실제로 바뀔 때만 억제).
    @State private var suppressPriceChange = false
    @State private var suppressEndChange = false
    // 결제(신규 예약 한정)
    @State private var markPaid = false
    @State private var payMethod: PaymentMethod = .card
    // 상태
    @State private var errorMessage: String?
    /// 저장 진행 중 재진입 차단(저장 버튼 disabled). 웹은 이 가드가 없어 연속 클릭 시
    /// 신규 고객이 두 벌 만들어졌다(tas 2026-07 수정). 앱은 @MainActor에서 await 전에
    /// 세우고, 신규 고객 id도 시트 생성 시점의 nextCustomerId 고정값이라 재시도해도 upsert된다.
    @State private var isSaving = false
    @State private var showConflictConfirm = false
    @FocusState private var focusedField: Field?

    private enum Field { case name, tel, price, memo }

    /// 결제완료 등록 시 선택 가능한 결제수단(적립금 사용은 상세 결제 화면에서).
    private static let paymentMethods: [PaymentMethod] = [
        .cash, .cashReceipt, .card, .naverPay, .localCurrency,
        .localCurrencyReceipt, .giftCard, .discount, .naverDeposit
    ]

    private static let seoul = TimeZone(identifier: "Asia/Seoul")!
    private var catalogMap: [String: ServiceItem] {
        Dictionary(catalog.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }
    private var totalDuration: Int { selectedServices.compactMap { catalogMap[$0]?.durationMinutes }.reduce(0, +) }
    private var totalPrice: Int { selectedServices.compactMap { catalogMap[$0]?.price }.reduce(0, +) }

    /// 고객명 추천 목록 — 이름 가나다순(웹 `sortCustomersByName`, tas #175).
    /// 등록 순(id)으로 6개를 자르면 흔한 이름일수록 엉뚱한 후보가 먼저 잘려 나간다.
    private var filteredCustomers: [Customer] {
        let q = customerName.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return customers.filter { $0.name.contains(q) || $0.tel.contains(q) }
            .sortedByName()
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                customerSection
                serviceSection
                priceSection
                assigneeSection
                dateTimeSection
                conflictSection
                paymentSection
                memoSection
                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(editing == nil ? "예약 추가" : "예약 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { attemptSave() }
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: setupInitial)
            .alert("담당자 겹침", isPresented: $showConflictConfirm) {
                Button("취소", role: .cancel) {}
                Button("그래도 저장", role: .destructive) { Task { await save() } }
            } message: {
                Text("선택한 담당자에게 시간이 겹치는 예약이 \(currentConflicts.count)건 있습니다. 그래도 저장하시겠어요?")
            }
        }
    }

    // MARK: - 담당자 겹침(중복 예약) 경고

    /// 현재 폼 선택(담당자·날짜·시간)과 겹치는 기존 예약. 서비스 미선택 시(시간 무의미) 빈 배열.
    private var currentConflicts: [Reservation] {
        guard !selectedServices.isEmpty else { return [] }
        return ReservationOverlap.conflicts(
            date: KST.dayKey.string(from: date),
            startTime: timeString(startTime),
            endTime: timeString(endTime),
            assigneeId: assigneeId == 0 ? nil : assigneeId,
            among: existingReservations,
            excludingId: editing?.id
        )
    }

    @ViewBuilder private var conflictSection: some View {
        let conflicts = currentConflicts
        if !conflicts.isEmpty {
            Section {
                ForEach(conflicts) { r in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(r.startTime)–\(r.endTime) · \(customerLabel(r.customerId))")
                                .font(.subheadline.weight(.medium))
                            if !r.service.isEmpty {
                                ServiceChipList(service: r.service, colorMap: serviceColorMap)
                            }
                        }
                    }
                }
            } header: {
                Text("담당자 겹침 경고")
            } footer: {
                Text("선택한 담당자에게 시간이 겹치는 예약이 \(conflicts.count)건 있습니다. 확인 후 저장하세요.")
            }
        }
    }

    private func customerLabel(_ id: Int) -> String {
        customers.first(where: { $0.id == id })?.name ?? "고객 #\(id)"
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

    /// 서비스 항목 행 — 웹처럼 체크박스(왼쪽) + 시술 칩 + "가격 · 소요시간"(오른쪽).
    private func serviceItemRow(_ item: ServiceItem) -> some View {
        let selected = selectedServices.contains(item.name)
        return Button { toggleService(item.name) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.accentColor : Color(.tertiaryLabel))
                ServiceChip(
                    name: item.name,
                    color: ServiceColor.color(item.name, in: serviceColorMap),
                    font: .subheadline
                )
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
        if !isPriceManual { setPrice(totalPrice) }
        errorMessage = nil
    }

    /// price를 프로그램적으로 설정(수동 플래그가 켜지지 않게 억제).
    private func setPrice(_ value: Int) {
        guard value != price else { return }
        suppressPriceChange = true
        price = value
    }

    /// endTime을 프로그램적으로 설정(수동 플래그가 켜지지 않게 억제).
    private func setEndTime(_ value: Date) {
        guard value != endTime else { return }
        suppressEndChange = true
        endTime = value
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
                .onChange(of: endTime) { _, _ in
                    if suppressEndChange { suppressEndChange = false } else { isEndManual = true }
                    errorMessage = nil
                }
        }
    }

    // MARK: - 가격 (웹: 서비스 바로 아래)

    private var priceSection: some View {
        Section("가격") {
            HStack {
                TextField("0", value: $price, format: .number)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .price)
                    .onChange(of: price) { _, _ in
                        if suppressPriceChange { suppressPriceChange = false } else { isPriceManual = true }
                    }
                Text("원").foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 결제 (신규 예약 한정 — 편집은 상세의 결제 화면 사용)

    @ViewBuilder private var paymentSection: some View {
        if editing == nil {
            Section {
                Toggle("결제완료로 등록", isOn: $markPaid)
                if markPaid {
                    Picker("결제수단", selection: $payMethod) {
                        ForEach(Self.paymentMethods, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            } header: {
                Text("결제")
            } footer: {
                if markPaid {
                    if pointRate > 0 {
                        Text("결제 \(formatWon(price)) · 적립률 \(pointRate)% → \(PointMath.earnedAmount(base: price, rate: pointRate).formatted())P 적립")
                    } else {
                        Text("결제 \(formatWon(price))로 결제완료 처리됩니다.")
                    }
                }
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
        if let editing {
            prefill(from: editing, cal: cal)
            return
        }
        date = initialDate
        // 시작 기본 10:00, 종료 +30분.
        let base = cal.date(bySettingHour: 10, minute: 0, second: 0, of: initialDate) ?? initialDate
        startTime = base
        setEndTime(cal.date(byAdding: .minute, value: 30, to: base) ?? base)
        assigneeId = assignees.first?.id ?? 0
    }

    /// 편집 모드: 기존 예약 값으로 폼을 채운다. 종료·가격은 수동으로 취급해 자동 재계산이 덮지 않게 한다.
    private func prefill(from r: Reservation, cal: Calendar) {
        customerId = r.customerId
        if let c = customers.first(where: { $0.id == r.customerId }) {
            customerName = c.name
            customerTel = c.tel
        }
        // knownNames는 카탈로그 이름이 아니라 **색 맵의 키**여야 한다 — 이름에 '+'가 든
        // 레거시 서비스("다운펌+커트")는 카탈로그엔 없고 색 맵에만 있어서, 카탈로그로 주면
        // greedy 보존이 아예 동작하지 않는다(웹도 Object.keys(serviceColorMap)를 넘긴다).
        selectedServices = ServiceColor.parseServiceString(
            r.service,
            knownNames: Set(serviceColorMap.keys)
        )
        date = parseDate(r.date, cal: cal) ?? initialDate
        startTime = parseTime(r.startTime, on: date, cal: cal) ?? date
        isEndManual = true
        setEndTime(parseTime(r.endTime, on: date, cal: cal) ?? startTime)
        if let p = r.price { price = p; isPriceManual = true }
        memo = r.memo ?? ""
        assigneeId = r.assigneeId ?? (assignees.first?.id ?? 0)
    }

    /// "YYYY-MM-DD" → Date(정오, KST) — 종일 표기의 경계 문제를 피하려 정오로.
    private func parseDate(_ s: String, cal: Calendar) -> Date? {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(timeZone: Self.seoul, year: p[0], month: p[1], day: p[2], hour: 12))
    }

    /// "HH:mm"을 주어진 날짜에 얹은 Date(KST).
    private func parseTime(_ s: String, on day: Date, cal: Calendar) -> Date? {
        let p = s.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: day)
    }

    private func recomputeEndTime() {
        guard totalDuration > 0 else { return }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.seoul
        setEndTime(cal.date(byAdding: .minute, value: totalDuration, to: startTime) ?? startTime)
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

    /// 저장 시도 — 유효성 통과 후, 담당자 겹침이 있으면 확인 알럿을, 없으면 바로 저장.
    private func attemptSave() {
        if let err = validate() { errorMessage = err; return }
        if currentConflicts.isEmpty {
            Task { await save() }
        } else {
            showConflictConfirm = true
        }
    }

    private func save() async {
        if let err = validate() { errorMessage = err; return }
        isSaving = true
        defer { isSaving = false }
        do {
            var resolvedCustomerId = customerId
            var resolvedCustomer: Customer? = customers.first { $0.id == customerId }
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
                resolvedCustomer = newCustomer
            }
            let trimmedMemo = memo.trimmingCharacters(in: .whitespaces)
            let resolvedMemo = trimmedMemo.isEmpty ? nil : trimmedMemo
            if let editing {
                // 편집: 기존 값 복사 후 폼이 다루는 필드만 덮어써 결제·네이버·상태 등은 보존.
                var updated = editing
                updated.date = KST.dayKey.string(from: date)
                updated.startTime = timeString(startTime)
                updated.endTime = timeString(endTime)
                updated.service = ServiceColor.joinServiceNames(selectedServices)
                updated.customerId = resolvedCustomerId
                updated.assigneeId = assigneeId == 0 ? nil : assigneeId
                updated.price = price
                updated.memo = resolvedMemo
                _ = try await service.updateReservation(prev: editing, updated: updated)
            } else {
                var reservation = Reservation(
                    id: nextReservationId,
                    date: KST.dayKey.string(from: date),
                    startTime: timeString(startTime),
                    endTime: timeString(endTime),
                    service: ServiceColor.joinServiceNames(selectedServices),
                    customerId: resolvedCustomerId,
                    assigneeId: assigneeId == 0 ? nil : assigneeId,
                    status: .active,
                    price: price,
                    memo: resolvedMemo,
                    channel: .phone
                )
                // 결제완료로 등록: 단일 결제수단 + 적립률 자동 적립.
                var earned = 0
                if markPaid {
                    earned = PointMath.earnedAmount(base: price, rate: pointRate)
                    reservation.paymentEntries = [PaymentEntry(method: payMethod, amount: price)]
                    reservation.paymentCompleted = true
                    reservation.paymentMethod = payMethod
                    reservation.pointEarned = earned
                }
                _ = try await service.createReservation(reservation)
                // 자동 적립을 고객 잔액에 반영.
                if markPaid, earned > 0, let c = resolvedCustomer,
                   let updated = PointLedger.apply(
                    to: c, previousEarned: 0, newEarned: earned, previousUsed: 0, newUsed: 0,
                    reservationId: reservation.id,
                    now: ISO8601DateFormatter().string(from: Date()), makeId: { UUID().uuidString }) {
                    _ = try await service.upsertCustomer(updated)
                }
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
