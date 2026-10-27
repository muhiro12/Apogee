import ApogeeCore
import ArgumentParser
import Foundation

struct ReleasePolicyOptions: ParsableArguments {
    @Option(help: "MANUAL, AFTER_APPROVAL, or SCHEDULED; defaults to MANUAL for creation and preserves the policy for updates.")
    var releaseType: String?
    @Option(help: "Future ISO 8601 timestamp with seconds and Z or a UTC offset; required only for SCHEDULED.")
    var earliestReleaseDate: String?

    func policy() throws -> VersionReleasePolicy? {
        switch (releaseType, earliestReleaseDate) {
        case (nil, nil):
            return nil
        case ("MANUAL", nil):
            return .manual
        case ("AFTER_APPROVAL", nil):
            return .afterApproval
        case let ("SCHEDULED", .some(value)):
            return .scheduled(try Self.parseDate(value))
        default:
            throw VersionSettingsError.invalidReleasePolicy
        }
    }

    private static func parseDate(_ value: String) throws -> Date {
        let pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            throw VersionSettingsError.invalidDate
        }
        let offset: Int
        if value.hasSuffix("Z") {
            offset = 0
        } else {
            let suffix = String(value.suffix(6))
            guard let hours = Int(suffix.dropFirst().prefix(2)), hours <= 23,
                  let minutes = Int(suffix.suffix(2)), minutes <= 59 else {
                throw VersionSettingsError.invalidDate
            }
            offset = (hours * 3_600 + minutes * 60) * (suffix.hasPrefix("-") ? -1 : 1)
            // RFC 3339 -00:00 denotes an unknown local offset, not a supplied zone.
            guard suffix != "-00:00" else {
                throw VersionSettingsError.invalidDate
            }
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        guard let timeZone = TimeZone(secondsFromGMT: offset) else {
            throw VersionSettingsError.invalidDate
        }
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), date > .now,
              formatter.string(from: date) == (value.hasSuffix("+00:00") ? String(value.dropLast(6)) + "Z" : value) else {
            throw VersionSettingsError.invalidDate
        }
        return date
    }
}
