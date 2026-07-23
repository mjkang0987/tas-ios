import SwiftUI

/// 담당자 추가/수정 폼 — 웹 `AssigneeManageSection` 이식.
///
/// 필드: 이름(필수) · 상태(재직/휴직/퇴직) · 컬러 · 연락처 · 메모 · 근무시간(재직일 때만).
/// 근무시간은 월~일 7행(요일별 사용 여부 + 시작/종료). 저장은 상위 목록에 upsert 후
/// 전체 목록을 PUT(웹 일괄 저장 모델). 성공 시에만 닫힌다.
struct AssigneeFormView: View {
    var editing: Assignee? = nil
    var nextId: Int = 0
    /// 편집한 담당자를 넘기고, 저장 성공 여부(Bool)를 돌려받는다.
    let onSave: (Assignee) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var status: AssigneeStatus = .active
    @State private var color = AssigneeFormView.colorPalette[0]
    @State private var phone = ""
    @State private var note = ""
    @State private var schedule: [DaySchedule] = ShopIndustry.defaultSchedule()
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// 담당자 색 팔레트(웹 자유 색상 대신 iOS 네이티브 감성의 큐레이션 팔레트; 기본 보라 포함).
    static let colorPalette = ["#6526D9", "#4285F4", "#34A853", "#EA4335", "#FBBC04", "#FF6D01", "#46BDC6", "#E91E8C"]
    static let weekdayLabels = ["월", "화", "수", "목", "금", "토", "일"]
    private static let seoul = TimeZone(identifier: "Asia/Seoul")!

    var body: some View {
        NavigationStack {
            Form {
                Section("담당자") {
                    TextField("이름", text: $name)
                    Picker("상태", selection: $status) {
                        Text("재직").tag(AssigneeStatus.active)
                        Text("휴직").tag(AssigneeStatus.leave)
                        Text("퇴직").tag(AssigneeStatus.retired)
                    }
                }

                Section("컬러") {
                    colorField
                }

                Section("연락처·메모") {
                    TextField("연락처 (010-0000-0000)", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("특이사항 메모", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                if status == .active {
                    Section("근무시간") {
                        ForEach(0..<7, id: \.self) { day in
                            scheduleRow(day)
                        }
                    }
                } else {
                    Section {
                        Text(status == .leave
                             ? "휴직 상태에서는 근무시간 설정을 접어 둡니다. 복귀 후 다시 조정할 수 있어요."
                             : "퇴직 상태에서는 예약 선택이 비활성화되며 근무시간을 표시하지 않습니다.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
                }
            }
            .navigationTitle(editing == nil ? "담당자 추가" : "담당자 수정")
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

    // MARK: - 컬러 팔레트

    private var colorField: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Self.colorPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if hex == color {
                                Circle().strokeBorder(.primary, lineWidth: 2.5)
                            }
                        }
                        .onTapGesture { color = hex }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - 근무시간 행

    private func scheduleRow(_ day: Int) -> some View {
        VStack(spacing: 4) {
            Toggle(isOn: enabledBinding(day)) {
                Text(Self.weekdayLabels[day]).font(.body.weight(.medium))
            }
            if schedule[day].enabled {
                HStack {
                    DatePicker("", selection: timeBinding(day, isStart: true), displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, Self.seoul)
                        .labelsHidden()
                    Text("–").foregroundStyle(.secondary)
                    DatePicker("", selection: timeBinding(day, isStart: false), displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, Self.seoul)
                        .labelsHidden()
                    Spacer()
                }
            }
        }
    }

    private func enabledBinding(_ day: Int) -> Binding<Bool> {
        Binding(get: { schedule[day].enabled }, set: { schedule[day].enabled = $0 })
    }

    private func timeBinding(_ day: Int, isStart: Bool) -> Binding<Date> {
        Binding(
            get: { date(from: isStart ? schedule[day].start : schedule[day].end) },
            set: { newValue in
                let text = hhmm(from: newValue)
                if isStart { schedule[day].start = text } else { schedule[day].end = text }
            }
        )
    }

    // MARK: - 시간 문자열 변환

    private func date(from hhmm: String) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Self.seoul
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        let base = Date(timeIntervalSinceReferenceDate: 0)
        return cal.date(bySettingHour: parts.first ?? 10, minute: parts.count > 1 ? parts[1] : 0, second: 0, of: base) ?? base
    }

    private func hhmm(from date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = Self.seoul
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: - 로직

    private func setup() {
        guard let editing else { return }
        name = editing.name
        status = editing.status ?? .active
        color = editing.color ?? Self.colorPalette[0]
        phone = editing.phone ?? ""
        note = editing.note ?? ""
        schedule = normalized(editing.schedule)
    }

    /// 스케줄을 항상 7개(월~일)로 맞춘다(모자라면 휴무로 채움).
    private func normalized(_ s: [DaySchedule]) -> [DaySchedule] {
        guard s.count != 7 else { return s }
        var out = s
        while out.count < 7 { out.append(DaySchedule(enabled: false, start: "10:00", end: "20:00")) }
        return Array(out.prefix(7))
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { errorMessage = "담당자 이름을 입력해주세요."; return }
        isSaving = true
        defer { isSaving = false }

        let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        let assignee = Assignee(
            id: editing?.id ?? nextId,
            name: trimmedName,
            nameI18n: editing?.nameI18n,
            schedule: schedule,
            status: status,
            phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            color: color
        )
        if await onSave(assignee) {
            dismiss()
        } else {
            errorMessage = "저장에 실패했습니다. 다시 시도해주세요."
        }
    }
}
