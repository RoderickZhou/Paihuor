import Foundation

extension Date {
    var epochMilliseconds: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }

    init(epochMilliseconds: Int64) {
        self.init(timeIntervalSince1970: TimeInterval(epochMilliseconds) / 1000)
    }
}

enum PaihuorDateFormatter {
    static func friendlyDeadline(_ milliseconds: Int64, now: Date = Date()) -> String {
        guard milliseconds > 0 else { return "未设截止时间" }

        let date = Date(epochMilliseconds: milliseconds)
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_CN")
        timeFormatter.dateFormat = "HH:mm"

        if calendar.isDateInToday(date) {
            return "今天 \(timeFormatter.string(from: date))"
        }

        if calendar.isDateInTomorrow(date) {
            return "明天 \(timeFormatter.string(from: date))"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "MM-dd HH:mm"
        return dateFormatter.string(from: date)
    }

    static func countdownText(_ milliseconds: Int64, now: Date = Date()) -> String? {
        guard milliseconds > 0 else { return nil }

        let deadline = Date(epochMilliseconds: milliseconds)
        let seconds = Int(deadline.timeIntervalSince(now))
        guard seconds > 0 else { return "已超时" }

        let hours = seconds / 3600
        let minutes = max(1, (seconds % 3600) / 60)

        if hours > 0 {
            return "还剩 \(hours) 小时 \(minutes) 分"
        }

        return "还剩 \(minutes) 分钟"
    }
}
