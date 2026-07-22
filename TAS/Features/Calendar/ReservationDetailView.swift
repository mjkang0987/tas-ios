import SwiftUI

/// 예약 상세 (읽기). 탭한 예약의 전체 정보를 시트로 보여준다.
struct ReservationDetailView: View {
    let reservation: Reservation
    let customer: Customer?
    let assignee: Assignee?
    var serviceColor: Color?
    var isNewCustomer: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("고객") {
                    LabeledContent("이름") {
                        HStack(spacing: 6) {
                            Text(customer?.name ?? "고객 #\(reservation.customerId)")
                            if isNewCustomer { NewCustomerBadge() }
                        }
                    }
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
                    LabeledContent("서비스") {
                        HStack(spacing: 6) {
                            if let serviceColor { ColorDot(color: serviceColor, size: 8) }
                            Text(reservation.service)
                        }
                    }
                    if let assignee {
                        LabeledContent("담당자") {
                            HStack(spacing: 6) {
                                ColorDot(color: Color(hex: assignee.color) ?? .gray)
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
                        LabeledContent("금액", value: formatWon(price))
                    }
                    LabeledContent("결제 완료", value: reservation.hasCompletedPayment ? "예" : "아니오")
                    if let entries = reservation.paymentEntries, !entries.isEmpty {
                        ForEach(Array(entries.enumerated()), id: \.offset) { item in
                            LabeledContent(item.element.method.rawValue, value: formatWon(item.element.amount))
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
