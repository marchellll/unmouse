import Foundation

/// Loads [`priority-words.txt`](priority-words.txt). Empty set only if every source fails.
///
/// Never touch `Bundle.module` — SPM's accessor `fatalError`s when the resource
/// bundle is missing (e.g. a hand-built `.app` that only copied the binary).
public enum PriorityWords {
    public static func load() -> Set<String> {
        if let text = loadText() { return parse(text) }
        return parse(embeddedFallback)
    }

    public static func parse(_ text: String) -> Set<String> {
        var words: Set<String> = []
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            words.insert(trimmed.lowercased())
        }
        return words
    }

    /// ponytail: mirror of priority-words.txt so a missing bundle cannot crash hint mode.
    private static let embeddedFallback = """
        ok
        save
        done
        open
        yes
        """

    private static func loadText() -> String? {
        for bundle in candidateBundles() {
            if let url = bundle.url(forResource: "priority-words", withExtension: "txt"),
               let text = try? String(contentsOf: url, encoding: .utf8)
            {
                return text
            }
        }
        return nil
    }

    private static func candidateBundles() -> [Bundle] {
        var out: [Bundle] = []
        let name = "Unmouse_UnmouseCore"

        if let nested = Bundle.main.url(forResource: name, withExtension: "bundle"),
           let bundle = Bundle(url: nested)
        {
            out.append(bundle)
        }
        out.append(Bundle.main)

        // swift run / .build/*/Unmouse next to Unmouse_UnmouseCore.bundle
        if let dir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let nearby = [
                dir.appendingPathComponent("\(name).bundle"),
                dir.appendingPathComponent("Contents/Resources/\(name).bundle"),
                dir.deletingLastPathComponent().appendingPathComponent("Resources/\(name).bundle"),
            ]
            for url in nearby {
                if let bundle = Bundle(url: url) { out.append(bundle) }
            }
        }
        return out
    }
}
