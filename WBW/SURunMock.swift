import Foundation

struct RankRow: Identifiable {
    let rank: Int
    let name: String
    let faculty: String
    let steps: Int
    var id: Int { rank }
}

/// ข้อมูลจำลอง SU RUN / RANKING (UI-only; แทนด้วยข้อมูลจริงเฟสหน้า)
enum SURunMock {
    static let selfName = "BANLANG"
    static let selfFaculty = "ADT"
    static let totalSteps = "1,555,500"
    static let totalDistance = "480 km."
    static let activityTime = "80 hr."
    static let calBurn = "75,000 Cal"

    static let leaderboard: [RankRow] = [
        RankRow(rank: 1, name: "BANLANG",       faculty: "ADT", steps: 1_200_000),
        RankRow(rank: 2, name: "WEERAPONG",     faculty: "ADT", steps: 1_000_000),
        RankRow(rank: 3, name: "MANATSANAN",    faculty: "SOM", steps:   900_000),
        RankRow(rank: 4, name: "KANTIMA",       faculty: "SOM", steps:   500_000),
        RankRow(rank: 5, name: "PATCHARAPOND",  faculty: "SOM", steps:   500_000),
        RankRow(rank: 6, name: "CHINAVORN",     faculty: "SOM", steps:   100_000),
        RankRow(rank: 7, name: "THANANYA",      faculty: "SOM", steps:    90_000),
        RankRow(rank: 8, name: "PHATTARANAREE", faculty: "CSC", steps:         3),
    ]

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}
