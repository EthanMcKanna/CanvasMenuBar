import Foundation

struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    init?(string: String) {
        var cleaned = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.hasPrefix("v") || cleaned.hasPrefix("V") {
            cleaned.removeFirst()
        }
        guard !cleaned.isEmpty else { return nil }

        let components = cleaned.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numericPart = components.first ?? Substring()
        let prereleasePart = components.count > 1 ? String(components[1]) : nil

        guard !numericPart.isEmpty else { return nil }
        let numberComponents = numericPart.split(separator: ".")
        guard let majorValue = numberComponents.first.flatMap({ Int($0) }) else { return nil }
        let minorValue = numberComponents.count > 1 ? Int(numberComponents[1]) ?? 0 : 0
        let patchValue = numberComponents.count > 2 ? Int(numberComponents[2]) ?? 0 : 0

        self.major = majorValue
        self.minor = minorValue
        self.patch = patchValue
        self.prerelease = prereleasePart?.isEmpty == true ? nil : prereleasePart
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _):
            return false
        case (_, nil):
            return true
        case let (lhsPre?, rhsPre?):
            return lhsPre.compare(rhsPre, options: .numeric) == .orderedAscending
        }
    }
}

extension SemanticVersion {
    var displayString: String {
        var version = "\(major).\(minor).\(patch)"
        if let prerelease {
            version += "-\(prerelease)"
        }
        return version
    }
}
