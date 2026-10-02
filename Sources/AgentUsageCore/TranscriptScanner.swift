import Foundation

/// Reads token usage from Claude Code's transcripts (`projects/**/*.jsonl`).
///
/// Transcripts are append-only and run to hundreds of megabytes, so each file is remembered by inode,
/// size and the byte offset already parsed; a refresh reads only what was appended since the last one.
public actor TranscriptScanner {
    private struct FileState {
        var inode: UInt64
        var size: UInt64
        var parsedOffset: UInt64
        var entries: [String: UsageEntry]
    }

    private let roots: [URL]
    private let horizon: TimeInterval
    private var files: [String: FileState] = [:]

    /// - Parameters:
    ///   - roots: directories holding project transcripts, normally `~/.claude/projects`.
    ///   - horizon: how far back usage is kept; files untouched for longer are not opened.
    public init(roots: [URL], horizon: TimeInterval = 31 * 86_400) {
        self.roots = roots
        self.horizon = horizon
    }

    /// Returns every deduplicated assistant message newer than the horizon.
    public func scan(now: Date = Date()) -> [UsageEntry] {
        let cutoff = now.addingTimeInterval(-horizon)
        let current = transcriptFiles(modifiedAfter: cutoff)
        files = files.filter { current[$0.key] != nil }
        for (path, attributes) in current {
            refresh(path: path, inode: attributes.inode, size: attributes.size)
        }
        return mergedEntries(newerThan: cutoff)
    }

    private func refresh(path: String, inode: UInt64, size: UInt64) {
        var state = files[path] ?? FileState(inode: inode, size: 0, parsedOffset: 0, entries: [:])
        if state.inode != inode || size < state.parsedOffset {
            state = FileState(inode: inode, size: 0, parsedOffset: 0, entries: [:])
        }
        guard size != state.size else { return }
        guard let appended = Self.read(path: path, from: state.parsedOffset) else { return }
        let consumed = Self.parseLines(appended, path: path, baseOffset: state.parsedOffset, into: &state.entries)
        state.parsedOffset += UInt64(consumed)
        state.size = size
        files[path] = state
    }

    /// The same message can be written to several transcripts (a resumed or forked session copies history);
    /// the first file in path order keeps it so totals don't depend on directory enumeration order.
    private func mergedEntries(newerThan cutoff: Date) -> [UsageEntry] {
        var merged: [String: UsageEntry] = [:]
        for path in files.keys.sorted() {
            guard let entries = files[path]?.entries else { continue }
            for (key, entry) in entries where entry.timestamp >= cutoff && merged[key] == nil {
                merged[key] = entry
            }
        }
        return Array(merged.values)
    }

    private func transcriptFiles(modifiedAfter cutoff: Date) -> [String: (inode: UInt64, size: UInt64)] {
        var found: [String: (inode: UInt64, size: UInt64)] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        for root in roots {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff,
                      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { continue }
                let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                found[url.path] = (inode, size)
            }
        }
        return found
    }

    private static func read(path: String, from offset: UInt64) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }

    /// Parses complete lines and returns how many bytes were consumed; a trailing partial line is left
    /// for the next refresh because Claude Code may still be writing it.
    static func parseLines(_ data: Data, path: String, baseOffset: UInt64, into entries: inout [String: UsageEntry]) -> Int {
        let newline = UInt8(ascii: "\n")
        var lineStart = data.startIndex
        var consumed = 0
        while let lineEnd = data[lineStart...].firstIndex(of: newline) {
            let line = data[lineStart..<lineEnd]
            let fallbackKey = "\(path)#\(baseOffset + UInt64(lineStart - data.startIndex))"
            if let parsed = parseLine(line, fallbackKey: fallbackKey) {
                // Streaming writes one line per content block with the same message id; the last carries final usage.
                entries[parsed.key] = parsed.entry
            }
            lineStart = data.index(after: lineEnd)
            consumed = lineStart - data.startIndex
        }
        return consumed
    }

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let assistantMarker = Data("assistant".utf8)

    /// Returns the dedupe key and entry for an assistant message that reports token usage.
    static func parseLine(_ line: Data, fallbackKey: String) -> (key: String, entry: UsageEntry)? {
        guard line.range(of: usageMarker) != nil, line.range(of: assistantMarker) != nil,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = object["message"] as? [String: Any],
              (object["type"] as? String) == "assistant" || (message["role"] as? String) == "assistant",
              let usagePayload = message["usage"] as? [String: Any],
              let timestampText = object["timestamp"] as? String,
              let timestamp = Timestamp.parse(timestampText) else { return nil }
        let model = (message["model"] as? String) ?? "claude"
        let usage = tokenUsage(usagePayload)
        guard usage.total > 0, model != "<synthetic>" else { return nil }
        let key = (message["id"] as? String).map { "\($0)|\(object["requestId"] as? String ?? "")" } ?? fallbackKey
        return (key, UsageEntry(timestamp: timestamp, model: model, usage: usage))
    }

    private static func tokenUsage(_ payload: [String: Any]) -> TokenUsage {
        func count(_ value: Any?) -> Int { (value as? NSNumber)?.intValue ?? 0 }
        let cacheCreation = count(payload["cache_creation_input_tokens"])
        let oneHour = min(cacheCreation, count((payload["cache_creation"] as? [String: Any])?["ephemeral_1h_input_tokens"]))
        return TokenUsage(
            input: count(payload["input_tokens"]),
            output: count(payload["output_tokens"]),
            cacheRead: count(payload["cache_read_input_tokens"]),
            cacheWrite5m: cacheCreation - oneHour,
            cacheWrite1h: oneHour
        )
    }
}
