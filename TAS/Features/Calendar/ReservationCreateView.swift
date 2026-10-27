import SwiftUI

/// 예약 생성 폼 — 웹 `ReservationCreate` + `useReservationCreateForm` 이식(핵심 필드).
///
/// 필드 순서/규칙은 웹과 동일:
/// 고객(기존 검색 or 신규 이름+연락처) → 서비스(다중선택, 소요시간·가격 자동) →
/// 담당자 → 날짜 → 시작/종료 시간(종료는 소요시간으로 자동) → 가격(자동, 수정 가능) → 예약경로 → 메모.
/// 저장 시 신규 고객이면 먼저 upsert 후 예약 생성(게스트=로컬/로그인=API 자동 분기).
/// 담당자 가용성(중복 예약)은 `ReservationOverlap`로 겹침을 감지해 경고·확인한다.
/// 신규 예약은 선택적으로 "결제완료로 등록"(단일 결제수단 + 적립률 자동 적립)할 수 있다.
struct ReservationCreateView: View {
    @Environment(SessionStore.self) private var session
    private var labels: StoreLabels { session.labels }
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
    @Environment(\.dynamicTypeSize) private var typeSize

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
    /// 웹 예약경로 — 기본 전화예약, 경로가 없던 옛 예약도 전화예약으로 본다(웹 reservationDetailUtils 와 같다).
    @State private var channel: ReservationChannel = .phone
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
            // 웹 예약 추가 레이어 — 이름 붙은 입력칸을 위에서 아래로(날짜·시간·담당자는 iOS 고르기 그대로)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    customerSection
                    serviceSection
                    priceSection
                    assigneeSection
                    dateTimeSection
                    channelSection
                    conflictSection
                    paymentSection
                    memoSection
                    if let errorMessage {
                        Text(errorMessage).font(.tasMedium).foregroundStyle(Color.dangerText)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(editing == nil ? "예약 추가" : "예약 변경")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 웹 저장 버튼처럼 보라 채움
                    Button("저장") { attemptSave() }
                        .primaryToolbarButton()
                        .disabled(isSaving)
                }
            }
            .onAppear(perform: setupInitial)
            .alert("\(labels.assignee) 겹침", isPresented: $showConflictConfirm) {
                Button("취소", role: .cancel) {}
                Button("그래도 저장", role: .destructive) { Task { await save() } }
            } message: {
                Text("선택한 \(labels.assignee)에게 시간이 겹치는 예약이 \(currentConflicts.count)건 있습니다. 그래도 저장하시겠어요?")
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
            VStack(alignment: .leading, spacing: 8) {
                Text("\(labels.assignee) 겹침 경고").font(.tasMedium.weight(.bold)).foregroundStyle(Color.warningText)
                ForEach(conflicts) { r in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warningText)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(r.startTime)–\(r.endTime) · \(customerLabel(r.customerId))")
                                .font(.tasBody.weight(.medium))
                            if !r.service.isEmpty {
                                ServiceChipList(service: r.service, colorMap: serviceColorMap)
                            }
                        }
                    }
                }
                Text("선택한 \(labels.assignee)에게 시간이 겹치는 예약이 \(conflicts.count)건 있습니다. 확인 후 저장하세요.")
                    .font(.tasSmall).foregroundStyle(Color.textSecondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.warningText.opacity(0.6)))
        }
    }

    private func customerLabel(_ id: Int) -> String {
        customers.first(where: { $0.id == id })?.name ?? "고객 #\(id)"
    }

    // MARK: - 고객

    private var customerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FormField(label: "고객명") {
                TextField("고객명 검색 또는 신규 입력", text: $customerName)
                    .focused($focusedField, equals: .name)
                    .onChange(of: customerName) { _, name in
                        if Self.keepsSelectedCustomer(id: customerId, name: name, in: customers) { return }
                        if customerId != 0 { customerId = 0; customerTel = "" }  // 이름 재입력 → 신규 전환
                        showSuggestions = true
                        errorMessage = nil
                    }
            }
            // 고객 전체를 거르고 정렬하는 값이라 한 번만 계산
            let suggestions = showSuggestions ? filteredCustomers : []
            if !suggestions.isEmpty {
                // 웹 자동완성 목록 — 입력칸 바로 아래 테두리 상자
                VStack(spacing: 0) {
                    ForEach(suggestions) { c in
                        Button {
                            selectCustomer(c)
                        } label: {
                            HStack {
                                Text(c.name).font(.tasBody)
                                Spacer()
                                Text(c.formattedTel).font(.tasSmall).foregroundStyle(Color.textSecondary)
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if c.id != suggestions.last?.id { Rectangle().fill(Color.dividerLine).frame(height: 1) }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderLine))
            }
            FormField(label: "연락처") {
                TextField("연락처", text: $customerTel, prompt: Text("01012345678"))
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .tel)
                    .disabled(customerId != 0)   // 기존 고객이면 자동 채움(수정 불가)
                    .foregroundStyle(customerId != 0 ? Color.textSecondary : Color.primary)
            }
        }
    }

    /// 이름이 바뀌어도 고른 고객을 그대로 둘지 — 추천을 고르거나 변경 화면을 채우며 이름이 그 고객 이름이 된 경우.
    /// (안 그러면 고른 고객이 바로 신규로 풀려 연락처가 비었다)
    static func keepsSelectedCustomer(id: Int, name: String, in customers: [Customer]) -> Bool {
        id != 0 && customers.first { $0.id == id }?.name == name
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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(labels.service)").font(.tasMedium).foregroundStyle(Color.textSecondary)
                Spacer()
                if !selectedServices.isEmpty {
                    Text("\(totalDuration)분 · \(formatWon(totalPrice))")
                        .font(.tasSmall).foregroundStyle(Color.textSecondary)
                }
            }
            // 웹: 테두리 상자 안에 카테고리별 체크 목록
            VStack(alignment: .leading, spacing: 0) {
                if catalog.isEmpty {
                    Text("등록된 \(labels.service.josa(.iGa)) 없습니다. 설정에서 먼저 추가해주세요.")
                        .font(.tasMedium).foregroundStyle(Color.textSecondary)
                        .padding(.vertical, 10)
                } else {
                    ForEach(serviceRows) { row in
                        switch row {
                        case .header(let category):
                            Text(category)
                                .font(.tasSmall.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                                .padding(.top, 8)
                                .accessibilityAddTraits(.isHeader)
                        case .item(let item):
                            serviceItemRow(item)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.borderLine))
        }
    }

    /// 서비스 항목 행 — 웹처럼 체크박스(왼쪽) + 시술 칩 + "가격 · 소요시간"(오른쪽).
    private func serviceItemRow(_ item: ServiceItem) -> some View {
        let selected = selectedServices.contains(item.name)
        return Button { toggleService(item.name) } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? Color.accentColor : Color(.tertiaryLabel))
                    .accessibilityHidden(true)
                ServiceChip(
                    name: item.name,
                    color: ServiceColor.color(item.name, in: serviceColorMap),
                    font: .tasBody
                )
                Spacer()
                Text("\(formatWon(item.price)) · \(item.durationMinutes)분")
                    .font(.tasSmall).foregroundStyle(Color.textSecondary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
            FormField(label: labels.assignee) {
                // 편집 대상의 담당자가 재직 목록에 없으면(퇴사) 그대로 저장된다 — 비어 보이지 않게 알린다
                SelectMenu(title: labels.assignee, value: assignees.first { $0.id == assigneeId }?.name
                           ?? (assigneeId == 0 ? "선택" : "기존 \(labels.assignee) 유지")) {
                    Picker("\(labels.assignee)", selection: $assigneeId) {
                        ForEach(assignees) { a in Text(a.name).tag(a.id) }
                    }
                }
                .onChange(of: assigneeId) { _, _ in errorMessage = nil }
            }
        }
    }

    // MARK: - 날짜/시간

    private var dateTimeSection: some View {
        // 웹: 날짜 한 줄, 시작·종료 나란히
        VStack(alignment: .leading, spacing: 12) {
            FormField(label: "날짜", bordered: false) {
                DatePicker("날짜", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.timeZone, Self.seoul)
            }
            // 큰 글자에서는 나란히 두면 잘린다 — 위아래로
            let pair = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            pair {
                FormField(label: "시작", bordered: false) {
                    DatePicker("시작", selection: $startTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.timeZone, Self.seoul)
                        .onChange(of: startTime) { _, _ in if !isEndManual { recomputeEndTime() }; errorMessage = nil }
                }
                FormField(label: "종료", bordered: false) {
                    DatePicker("종료", selection: $endTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.timeZone, Self.seoul)
                        .onChange(of: endTime) { _, _ in
                            if suppressEndChange { suppressEndChange = false } else { isEndManual = true }
                            errorMessage = nil
                        }
                }
            }
        }
    }

    // MARK: - 예약경로 (웹: 시간 아래)

    /// 웹 select 는 셋뿐. 온라인 신청으로 들어온 예약을 변경할 때는 그 값도 남겨 보여 준다(안 그러면 '전화예약'처럼 보였다).
    private var channelOptions: [ReservationChannel] {
        let base: [ReservationChannel] = [.phone, .walkIn, .naver]
        return base.contains(channel) ? base : [channel] + base
    }

    private var channelSection: some View {
        FormField(label: "예약경로") {
            SelectMenu(title: "예약경로", value: channel.rawValue) {
                Picker("예약경로", selection: $channel) {
                    ForEach(channelOptions, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
        }
    }

    // MARK: - 가격 (웹: 서비스 바로 아래)

    private var priceSection: some View {
        FormField(label: "가격") {
            HStack {
                TextField("가격", value: $price, format: .number, prompt: Text("0"))
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .price)
                    .onChange(of: price) { _, _ in
                        if suppressPriceChange { suppressPriceChange = false } else { isPriceManual = true }
                    }
                Text("원").foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: - 결제 (신규 예약 한정 — 편집은 상세의 결제 화면 사용)

    @ViewBuilder private var paymentSection: some View {
        if editing == nil {
            VStack(alignment: .leading, spacing: 12) {
                Rectangle().fill(Color.dividerLine).frame(height: 1)
                Toggle("결제완료로 등록", isOn: $markPaid)
                    .font(.tasBody)
                    .tint(.brandFill)
                if markPaid {
                    FormField(label: "결제수단") {
                        SelectMenu(title: "결제수단", value: payMethod.rawValue) {
                            Picker("결제수단", selection: $payMethod) {
                                ForEach(Self.paymentMethods, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                        }
                    }
                    Group {
                        if pointRate > 0 {
                            Text("결제 \(formatWon(price)) · 적립률 \(pointRate)% → \(formatWon(PointMath.earnedAmount(base: price, rate: pointRate))) 적립")
                        } else {
                            Text("결제 \(formatWon(price))로 결제완료 처리됩니다.")
                        }
                    }
                    .font(.tasSmall).foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - 메모

    private var memoSection: some View {
        FormField(label: "요청사항") {
            TextField("예약 관련 요청사항", text: $memo, axis: .vertical)
                .focused($focusedField, equals: .memo)
                .lineLimit(1...3)
                .padding(.vertical, 8)
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
        channel = r.channel ?? .phone
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
        if !assignees.isEmpty && assigneeId == 0 { return "\(labels.assignee.josa(.eulReul)) 선택해주세요." }
        if customerName.trimmingCharacters(in: .whitespaces).isEmpty { return "고객명을 입력해주세요." }
        let isNew = customerId == 0
        let tel = normalizeTel(customerTel)
        if isNew && customerTel.trimmingCharacters(in: .whitespaces).isEmpty { return "연락처를 입력해주세요." }
        if isNew && tel.range(of: Self.mobilePattern, options: .regularExpression) == nil {
            return "연락처 형식을 확인해주세요."
        }
        if selectedServices.isEmpty { return "\(labels.service.josa(.eulReul)) 선택해주세요." }
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
                // 서버가 번호를 다시 정할 수 있다 — 돌려받은 고객(번호)으로 예약을 건다
                let saved = try await service.createCustomer(newCustomer)
                resolvedCustomerId = saved.id
                resolvedCustomer = saved
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
                updated.channel = channel
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
                    channel: channel
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
                    try await service.updateCustomer(updated)
                }
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
