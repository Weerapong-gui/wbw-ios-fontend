import SwiftUI

/// SU RUN — แดชบอร์ดกิจกรรม (Figma 163:36) · light mode · UI-only (mock)
struct SURunView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.wbwCream.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        Text("SUSU RUN")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(Color.wbwInk)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 12)

                        selfRankPill
                        statGrid
                        mapBlock
                        startButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    private var selfRankPill: some View {
        HStack(spacing: 10) {
            Text("1st")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 4).background(Color.wbwGold, in: Capsule())
            Text(SURunMock.selfName).font(.system(size: 15, weight: .heavy)).foregroundStyle(Color.wbwInk)
            Text(SURunMock.selfFaculty).font(.system(size: 11)).foregroundStyle(Color(white: 0.5))
            Spacer()
            NavigationLink {
                SURunRankingView()
            } label: {
                HStack(spacing: 4) { Text("RANKING"); Image(systemName: "chevron.right") }
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.wbwGreen)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassSurface(RoundedRectangle(cornerRadius: 16))
    }

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statTile("figure.walk", "Total steps", SURunMock.totalSteps)
            statTile("map", "Total distance", SURunMock.totalDistance)
            statTile("clock", "Activity Time", SURunMock.activityTime)
            statTile("flame", "Cal burn", SURunMock.calBurn)
        }
    }

    private func statTile(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(label, systemImage: icon)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.wbwGreen)
            Text(value).font(.system(size: 26, weight: .heavy)).foregroundStyle(Color.wbwInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    // placeholder: บล็อก MAP — no-op จนกว่าฟีเจอร์วิ่งจริงจะมา
    private var mapBlock: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 18).fill(Color.wbwGreen.opacity(0.12)).frame(height: 150)
            Text("MAP").font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color.wbwGreen.opacity(0.5)).padding(16)
        }
    }

    // placeholder: ยังไม่มี run session
    private var startButton: some View {
        Button { } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right")
                Text("Start now!").font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Color.wbwGreen, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview { SURunView() }
