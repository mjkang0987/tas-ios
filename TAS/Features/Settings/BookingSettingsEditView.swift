import SwiftUI

/// 온라인 예약 설정 — 웹 `BookingManageSection`(설정 > 고객 예약 설정) 이식.
///
/// 공개 예약 페이지(웹 전용)의 **주소와 규칙**을 앱에서 설정한다. 저장은
/// `PATCH /api/store`(`bookingSlug` + `bookingSettings`).
/// 게스트 모드는 공개 페이지 자체가 없어 로그인 게이트로 막는다.
struct BookingSettingsEditView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    var service = TASService()

    @State private var slug = ""
    @State private var settings = BookingSettings()
    @State private var serviceNames: [String] = []
    @State private var slugCheck: SlugCheck = .idle
    @State private var errorMessage: String?
    @State private var isSaving = false

    /// 슬러그 중복 확인 상태 — 웹 checkState.
    private enum SlugCheck: Equatable {
        case idle, checking, available, taken, invalid
    }

    private var trimmedSlug: String { slug.trimmingCharacters(in: .whitespaces).lowercased() }
    private var slugFormatInvalid: Bool { !trimmedSlug.isEmpty && !BookingSettings.isValidSlug(trimmedSlug) }
    private var contactRaw: String { (settings.contactTel ?? "").trimmingCharacters(in: .whitespaces) }
    private var contactFormatInvalid: Bool { !contactRaw.isEmpty && !BookingSettings.isValidContactTel(contactRaw) }

    var body: some View {
        NavigationStack {
            Group {
                if session.isGuest {
                    ContentUnavailableView(
                        "로그인 후 이용",
                        systemImage: "lock",
                        description: Text("공개 예약 페이지는 서버에서 열리기 때문에 온라인 예약 설정은 로그인 후에 할 수 있어요.")
                    )
                } else {
                    form
                }
            }
            .navigationTitle("온라인예약 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                if !session.isGuest {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { Task { await save() } }
                            .disabled(isSaving)
                    }
                }
            }
            .task { await setup() }
        }
    }

    private var form: some View {
        Form {
            Section {
                HStack {
                    TextField("예) mystore", text: $slug)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: slug) { slugCheck = .idle }
                    Button("중복 확인") { Task { await checkSlug() } }
                        .buttonStyle(.borderless)
                        .disabled(trimmedSlug.isEmpty || slugFormatInvalid || slugCheck == .checking)
                }
                if !trimmedSlug.isEmpty && !slugFormatInvalid {
                    LabeledContent("공개 주소") {
                        Text(AppConfig.bookingPublicURL(slug: trimmedSlug))
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } header: {
                Text("영문 매장명 (필수)")
            } footer: {
                if slugFormatInvalid {
                    Text("영문 소문자·숫자·하이픈 3~32자, 하이픈으로 시작·끝 불가.").foregroundStyle(.red)
                } else {
                    switch slugCheck {
                    case .available: Text("사용 가능한 주소입니다.").foregroundStyle(.green)
                    case .taken: Text("이미 사용 중인 주소입니다. 다른 값을 입력해 주세요.").foregroundStyle(.red)
                    case .invalid: Text("형식을 확인해 주세요.").foregroundStyle(.red)
                    case .checking: Text("확인 중…")
                    case .idle: Text("영문 매장명이 예약 페이지 주소가 됩니다.")
                    }
                }
            }

            Section {
                TextField("02-1234-5678", text: Binding(
                    get: { settings.contactTel ?? "" },
                    set: { settings.contactTel = $0 }
                ))
                .keyboardType(.phonePad)
            } header: {
                Text("매장 연락처 (필수)")
            } footer: {
                if contactFormatInvalid {
                    Text("숫자와 하이픈만 8~20자로 입력해 주세요.").foregroundStyle(.red)
                } else {
                    // 정책 문서·예약 페이지가 이 번호를 그대로 노출한다(입력 원문 유지).
                    Text("고객이 예약 문의와 개인정보 열람·삭제를 요구할 창구입니다. 예약 페이지와 개인정보 안내에 표시됩니다.")
                }
            }

            Section("예약 규칙") {
                Picker("예약 시간 간격", selection: $settings.slotIntervalMin) {
                    ForEach(BookingSettings.slotOptions, id: \.self) { Text("\($0)분").tag($0) }
                }
                numberRow("최소 사전 예약 시간", value: $settings.minLeadMinutes, range: 0...43200, unit: "분")
                numberRow("최대 예약 가능 일수", value: $settings.maxAdvanceDays, range: 1...365, unit: "일")
                Toggle("고객이 담당자 선택", isOn: $settings.allowAssigneeChoice)
            }

            Section {
                Text("지금부터 최소 사전 예약 시간 이내의 슬롯은 예약할 수 없어요. 담당자 선택을 끄면 매장이 배정합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                noticeField("사전 안내문", text: $settings.noticeText, caption: "예약 페이지 상단(예약 시작 전)")
                noticeField("예약완료 안내문", text: $settings.doneText, caption: "고객이 신청을 마친 완료 화면")
                noticeField("예약 확정 안내문", text: $settings.confirmText, caption: "확정 후 고객이 예약 조회 페이지를 열면")
                noticeField("예약 취소 안내문", text: $settings.cancelText, caption: "취소 후 고객이 예약 조회 페이지를 열면")
            } header: {
                Text("안내문구")
            } footer: {
                Text("기본 문구가 채워져 있어요. 그대로 쓰거나 매장에 맞게 고쳐 주세요. 비우면 표시되지 않습니다.")
            }

            if !serviceNames.isEmpty {
                Section {
                    ForEach(serviceNames, id: \.self) { name in
                        Button {
                            toggleServiceExposure(name)
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                if isServiceExposed(name) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("노출 서비스")
                } footer: {
                    Text("고객 예약 페이지에 보여줄 서비스입니다. 전체 선택이면 전체 노출로 저장됩니다.")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
        }
    }

    /// 숫자 입력 + 서버 허용 범위로 클램프(서버는 범위 밖이면 400 `Invalid bookingSettings`).
    private func numberRow(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: value.wrappedValue) { _, new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value.wrappedValue = clamped }
                }
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func noticeField(_ title: String, text: Binding<String?>, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(caption, text: Binding(
                get: { text.wrappedValue ?? "" },
                set: { text.wrappedValue = $0.isEmpty ? nil : $0 }
            ), axis: .vertical)
            .lineLimit(2...6)
        }
    }

    // MARK: - 노출 서비스 (웹 동일: 전체 선택 = nil로 저장)

    private func isServiceExposed(_ name: String) -> Bool {
        settings.bookableServiceNames?.contains(name) ?? true
    }

    private func toggleServiceExposure(_ name: String) {
        var current = Set(settings.bookableServiceNames ?? serviceNames)
        if current.contains(name) { current.remove(name) } else { current.insert(name) }
        let next = serviceNames.filter { current.contains($0) }
        settings.bookableServiceNames = next.count == serviceNames.count ? nil : next
    }

    // MARK: - Load / Save

    private func setup() async {
        guard !session.isGuest else { return }
        let store = session.currentStore
        slug = store?.bookingSlug ?? ""
        // 안내문구는 비어 있으면 기본 문구로 채워 보여준다(웹 동일) — 오너가 빈 칸을 마주하지 않게.
        settings = (store?.bookingSettings ?? BookingSettings()).withDefaultTexts()
        if let names = try? await service.fetchServices().services.map(\.name) {
            serviceNames = names
        }
    }

    private func checkSlug() async {
        guard BookingSettings.isValidSlug(trimmedSlug) else { slugCheck = .invalid; return }
        slugCheck = .checking
        do {
            let available = try await service.checkBookingSlug(trimmedSlug)
            slugCheck = available ? .available : .taken
        } catch {
            slugCheck = .idle
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func save() async {
        errorMessage = nil
        // 슬러그·연락처는 웹과 동일하게 필수. 연락처는 서버도 온라인예약이 켜져 있으면 400으로 막는다.
        if trimmedSlug.isEmpty { errorMessage = "영문 매장명은 필수입니다."; return }
        if slugFormatInvalid { errorMessage = "영문 매장명 형식이 올바르지 않습니다."; return }
        if contactRaw.isEmpty { errorMessage = "매장 연락처는 필수입니다."; return }
        if contactFormatInvalid { errorMessage = "매장 연락처 형식이 올바르지 않습니다."; return }
        guard let current = session.currentStore else { errorMessage = "매장 정보를 불러오지 못했습니다."; return }

        isSaving = true
        defer { isSaving = false }
        var payload = settings
        payload.contactTel = contactRaw
        do {
            let updated = try await service.updateBookingSettings(current: current, slug: trimmedSlug, settings: payload)
            session.currentStore = updated
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
