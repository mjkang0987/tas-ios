import SwiftUI

/// 예약 상세 (읽기). 탭한 예약의 전체 정보를 시트로 보여준다.
struct ReservationDetailView: View {
    let reservation: Reservation
    let customer: Customer?
    let assignee: Assignee?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("고객") {
                    LabeledContent("이름", value: customer?.name ?? "고객 #\(reservation.customerId)")
                    if let tel = customer?.formattedTel, !tel.isEmpty {
                        LabeledContent("연락처", value: tel)
                    }
                    if let points = customer?.points, points > 0 {
                        LabeledContent("적립금", value: "\(points.formatted())P")
                    }
                }

                Section("예약") {
                    LabeledContent("날짜", value: reservation.date)
                    LabeledContent("시간", value: "\(reservation.startTime) – \(reservation.endTime)")
                    LabeledContent("서비스", value: reservation.service)
                    if let assignee {
                        LabeledContent("담당자") {
                            HStack(spacing: 6) {
                                if let color = Color(hex: assignee.color) {
                                    Circle().fill(color).frame(width: 8, height: 8)
                                }
                                Text(assignee.name)
                            }
                        }
                    }
                    LabeledContent("상태") { StatusBadge(state: reservation.displayState) }
                    if let channel = reservation.channel {
                        LabeledContent("경로", value: channel.rawValue)
                    }
                }

                Section("결제") {
                    if let price = reservation.price {
                        LabeledContent("금액", value: "\(price.formatted())원")
                    }
                    LabeledContent("결제 완료", value: reservation.hasCompletedPayment ? "예" : "아니오")
                    if let entries = reservation.paymentEntries, !entries.isEmpty {
                        ForEach(Array(entries.enumerated()), id: \.offset) { item in
                            LabeledContent(item.element.method.rawValue, value: "\(item.element.amount.formatted())원")
                        }
                    } else if let method = reservation.paymentMethod {
                        LabeledContent("수단", value: method.rawValue)
                    }
                    if let earned = reservation.pointEarned, earned != 0 {
                        LabeledContent("적립", value: "\(earned.formatted())P")
                    }
                }

                if let memo = reservation.memo, !memo.isEmpty {
                    Section("메모") { Text(memo) }
                }
            }
            .navigationTitle("예약 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }
}
