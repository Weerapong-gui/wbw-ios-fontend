import Foundation

/// จัดการข้อมูลกลุ่ม — รายการกลุ่ม + ดัชนีสมาชิก (เบา) + สมาชิกเต็ม (lazy) + ค้นหา
@MainActor
final class GroupStore: ObservableObject {
    @Published var groups: [GroupSummary] = []
    @Published var memberIndex: [GroupMemberIndex] = []      // เบา (ไม่มีรูป) — ทุกกลุ่ม
    @Published var membersByGroup: [Int: [GroupMember]] = [:] // เต็ม (มีรูป) — โหลดตอนเปิดกลุ่ม
    @Published var search = ""
    @Published var loaded = false

    func load(token: String) async {
        guard !token.isEmpty else { return }
        async let g = APIClient.shared.groups(token: token)
        async let idx = APIClient.shared.membersIndex(token: token)
        if let gg = try? await g { groups = gg }
        if let ii = try? await idx { memberIndex = ii }
        loaded = true
    }

    /// สมาชิกเต็มของกลุ่ม (cache)
    func members(groupId: Int, token: String) async -> [GroupMember] {
        if let cached = membersByGroup[groupId] { return cached }
        if let r = try? await APIClient.shared.groupMembers(token: token, groupId: groupId) {
            membersByGroup[groupId] = r.members
            return r.members
        }
        return []
    }

    func join(groupId: Int, token: String) async throws {
        try await APIClient.shared.joinGroup(token: token, groupId: groupId)
    }

    /// preview สมาชิก (ตัวอักษร) จากดัชนี
    func indexMembers(groupId: Int) -> [GroupMemberIndex] {
        memberIndex.filter { $0.groupId == groupId }
    }

    // ===== ค้นหา (ทั้งกลุ่มและคน) =====
    var isNumericSearch: Bool {
        let s = search.trimmingCharacters(in: .whitespaces)
        return !s.isEmpty && s.allSatisfy { $0.isNumber }
    }

    var filteredGroups: [GroupSummary] {
        let s = search.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return groups }
        if isNumericSearch { return groups.filter { String($0.groupNumber).contains(s) } }
        let matched = Set(memberIndex.filter { $0.fullName.localizedCaseInsensitiveContains(s) }.map { $0.groupId })
        return groups.filter { matched.contains($0.groupId) }
    }

    /// คนที่ตรงคำค้น (โชว์เป็นผลลัพธ์แยกเวลาค้นด้วยชื่อ)
    var matchedPeople: [GroupMemberIndex] {
        let s = search.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !isNumericSearch else { return [] }
        return memberIndex.filter { $0.fullName.localizedCaseInsensitiveContains(s) }
    }
}
