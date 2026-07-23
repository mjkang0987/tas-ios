import SwiftUI

/// 영업시간·휴무일 설정 — 웹 StoreManageSection의 businessHours/closedWeekdays/closedDates 이식.
///
/// 영업시간(전체 공통 오픈/마감) + 정기 휴무 요일(월~일) + 특정 휴무일(날짜)을 편집한다.
/// 저장은 PUT /api/store(게스트=로컬). 담당자 개별 스케줄과는 별개의 매장 단위 설정.
struct StoreHoursEditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var service = TASService()

    @State private var start = Date()
    @State private var end = Date()
    @State private var closedWeekdays: Set<Int> = []
    @State private var closedDates: [String] = []
    @State private var newClosedDate = Date()
    @State private var errorMessage: String?
    @State private var isSaving = false

    private static let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]
    private static let seoul = TimeZone(identifier: "Asia/Seoul")!

    var body: some View {
        NavigationStack {
            Form {
                Section("영업시간") {
                    DatePicker("오픈", selection: $start, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, Self.seoul)
                    DatePicker("마감", selection: $end, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, Self.seoul)
                }

                Section {
                    ForEach(0..<7, id: \.self) { day in
                        Toggle(Self.weekdayLabels[day], isOn: Binding(
                            get: { closedWeekdays.contains(day) },
                            set: { on in if on { closedWeekdays.insert(day) } else { closedWeekdays.remove(day) } }
                        ))
                    }
                } header: {
                    Text("정기 휴무 요일")
                } footer: {
                    Text("체크한 요일은 매주 휴무로 처리됩니다.")
                }

                Section("휴무일") {
                    ForEach(closedDates, id: \.self) { d in
                        Text(d).monospacedDigit()
                    }
                    .onDelete { closedDates.remove(atOffsets: $0) }
                    HStack {
                        DatePicker("추가", selection: $newClosedDate, displayedComponents: .date)
                            .environment(\.timeZone, Self.seoul)
                        Button("추가", action: addClosedDate)
                            .buttonStyle(.borderless)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle("영업시간·휴무")
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
            .onAppear(perform: setup)
        }
    }

    private func addClosedDate() {
        let key = KST.dayKey.string(from: newClosedDate)
        if !closedDates.contains(key) {
            closedDates.append(key)
            closedDates.sort()
        }
    }

    private func setup() {
        let hours = session.currentStore?.businessHours ?? BusinessHours(start: "10:00", end: "20:00")
        start = date(from: hours.start)
        end = date(from: hours.end)
        closedWeekdays = Set(session.currentStore?.closedWeekdays ?? [])
        closedDates = (session.currentStore?.closedDates ?? []).sorted()
    }

    private func date(from hhmm: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.seoul
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        let base = Date(timeIntervalSinceReferenceDate: 0)
        return cal.date(bySettingHour: p.first ?? 10, minute: p.count > 1 ? p[1] : 0, second: 0, of: base) ?? base
    }

    private func hhmm(from date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = Self.seoul
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func save() async {
        let hours = BusinessHours(start: hhmm(from: start), end: hhmm(from: end))
        if hours.start >= hours.end { errorMessage = "오픈 시간은 마감보다 앞서야 합니다."; return }
        guard let current = session.currentStore else { errorMessage = "매장 정보를 불러오지 못했습니다."; return }
        isSaving = true
        defer { isSaving = false }
        do {
            let updated = try await service.updateSchedule(
                current: current,
                businessHours: hours,
                closedDates: closedDates,
                closedWeekdays: closedWeekdays.sorted()
            )
            session.currentStore = updated
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
