import SwiftUI

/// SU RUN RANKING — leaderboard (Figma 179:59) · light mode
struct SURunRankingView: View {
    private let rows = SURunMock.leaderboard
    private var maxSteps: Int { rows.map(\.steps).max() ?? 1 }

    var body: some View {
        ZStack {
            Color.wbwCream.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Text("RANKING")
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(Color.wbwInk)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    HStack(spacing: 10) {
                        Text("1st")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.wbwGold, in: Capsule())
                        Text("You on the podium")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.wbwInk)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassSurface(Capsule())
                    .padding(.bottom, 6)

                    ForEach(rows) { row in rankRow(row) }
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rankRow(_ row: RankRow) -> some View {
        let frac = max(0.12, Double(row.steps) / Double(maxSteps))
        return HStack(spacing: 10) {
            Text(SURunMock.ordinal(row.rank))
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Color.wbwInk)
                .frame(width: 34, alignment: .leading)
            Text(row.name).font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.wbwInk)
            Text(row.faculty).font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.5))
            Spacer(minLength: 6)
            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    Capsule().fill(Color.wbwGreen.opacity(0.15))
                    Capsule()
                        .fill(LinearGradient(colors: [Color.wbwGreen, Color.wbwGreen.opacity(0.6)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * frac)
                    Text("\(row.steps.formatted()) STEPS")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.trailing, 10)
                }
            }
            .frame(width: 170, height: 44)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { SURunRankingView() }
}
