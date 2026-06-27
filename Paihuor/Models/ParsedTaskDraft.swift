import Foundation

struct ParsedTaskDraft: Equatable {
    var title: String
    var detail: String
    var deadline: Int64

    var hasDeadline: Bool {
        deadline > 0
    }
}
