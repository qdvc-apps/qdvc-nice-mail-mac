import Foundation
import XCTest
@testable import NiceMailCore

/// Checks NiceMailCore against reference outputs recorded in
/// `Fixtures/parity.json`, which were produced by the Python/GTK edition of
/// QDVC Nice Mail. The fixture is committed, so these tests need nothing
/// else; see docs/MAINTENANCE.md §5 for how to regenerate it.
final class ParityTests: XCTestCase {
    typealias JSON = [String: Any]

    private static let fixtures: JSON = {
        guard let url = Bundle.module.url(forResource: "parity", withExtension: "json",
                                          subdirectory: "Fixtures") else {
            fatalError("parity.json missing from test bundle")
        }
        do {
            let data = try Data(contentsOf: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? JSON else {
                fatalError("parity.json is not an object")
            }
            return json
        } catch {
            fatalError("Could not read parity.json: \(error)")
        }
    }()

    private static let catalogue = EmojiCatalogue()

    private var fx: JSON { Self.fixtures }

    private func list(_ key: String) -> [Any] { fx[key] as? [Any] ?? [] }

    // MARK: - Naming and emoji

    func testEmojiID() {
        for case let pair as [String] in list("emoji_id") {
            XCTAssertEqual(Naming.emojiID(pair[0]), pair[1], pair[0])
        }
    }

    func testCustomGlyphs() {
        for case let triple as [String] in list("custom") {
            XCTAssertEqual(Naming.customEmojiID(triple[0]), triple[1])
            let custom = Self.catalogue.makeCustom(triple[0])
            XCTAssertEqual(custom.id, triple[1])
            XCTAssertEqual(custom.name, triple[2])
            XCTAssertTrue(custom.isCustom)
        }
    }

    func testSkinToneDisplay() {
        for case let triple as [String] in list("display") {
            let tone = SkinTone(rawValue: triple[1])!
            XCTAssertEqual(Emoji(id: "x", char: triple[0], name: "x").display(skinTone: tone), triple[2],
                           "\(triple[0]) \(triple[1])")
        }
        // Custom glyphs never take a tone.
        let custom = Emoji(id: "c", char: "\u{1F44B}", name: "c", isCustom: true)
        XCTAssertEqual(custom.display(skinTone: .dark), "\u{1F44B}")
    }

    /// Every entry the Python edition lists must exist here with the same id,
    /// glyph and name, and in the same relative order. (A newer macOS may know
    /// a few more characters; those are allowed in between.)
    func testCatalogueMatchesPython() {
        let expected = list("catalogue").compactMap { $0 as? [String] }
        XCTAssertGreaterThan(expected.count, 2000)
        var position: [String: Int] = [:]
        for (i, emoji) in Self.catalogue.all.enumerated() { position[emoji.id] = i }
        var last = -1
        var missing: [String] = []
        for entry in expected {
            let cps = entry[1].split(separator: " ").compactMap { UInt32($0, radix: 16) }
            let char = String(String.UnicodeScalarView(cps.compactMap(Unicode.Scalar.init)))
            guard let emoji = Self.catalogue.emoji(id: entry[0]) else {
                missing.append(entry[0])
                continue
            }
            XCTAssertEqual(emoji.char, char, entry[0])
            XCTAssertEqual(emoji.name, entry[2], entry[0])
            let p = position[entry[0]]!
            XCTAssertGreaterThan(p, last, "order of \(entry[0])")
            last = p
        }
        XCTAssertEqual(missing, [], "ids missing from the Swift catalogue")
    }

    func testSearch() {
        for case let item as [Any] in list("search") {
            let query = item[0] as! String
            let ids = item[1] as! [String]
            let count = item[2] as! Int
            let got = Self.catalogue.search(query)
            XCTAssertEqual(Array(got.map(\.id).prefix(ids.count)), ids, query)
            XCTAssertGreaterThanOrEqual(got.count, count, query)
        }
    }

    // MARK: - Signature and note

    func testSignature() {
        for case let c as JSON in list("signature") {
            let profile = (c["profile"] as? [String]).map { Profile(name: "p", lines: $0) }
            let got = Signature.assemble(signoff: c["signoff"] as! String, profile: profile,
                                         disclaimer: c["disclaimer"] as! String,
                                         includeDisclaimer: c["include"] as! Bool,
                                         messageRef: c["ref"] as! String,
                                         refOnly: c["ref_only"] as! Bool)
            XCTAssertEqual(got, c["out"] as! String)
        }
    }

    func testNoteBody() {
        for case let pair as [String] in list("note_body") {
            XCTAssertEqual(Note.body(text: pair[0], messageRef: "ABCDEFGHJK"), pair[1])
        }
    }

    func testDefaultFilename() {
        for case let item as [Any] in list("filename") {
            let date = Date(timeIntervalSince1970: TimeInterval(item[0] as! Int))
            let tz = TimeZone(secondsFromGMT: item[1] as! Int)!
            XCTAssertEqual(Note.defaultFilename(messageRef: "ABCDEFGHJK", date: date, timeZone: tz),
                           item[2] as! String)
        }
    }

    /// The body (and its Content-Transfer-Encoding) must be byte-identical to
    /// Python's. Headers must be too for short ASCII values; otherwise both
    /// must decode to the same text, with the other headers identical.
    func testEML() {
        for case let c as JSON in list("eml") {
            let date = Date(timeIntervalSince1970: TimeInterval(c["timestamp"] as! Int))
            let tz = TimeZone(secondsFromGMT: c["offset"] as! Int)!
            let data = Note.buildEML(address: c["address"] as! String, subject: c["subject"] as! String,
                                     text: c["text"] as! String, messageRef: c["ref"] as! String,
                                     date: date, timeZone: tz)
            let expected = Data(base64Encoded: c["eml"] as! String)!
            let label = "\(c["address"]!) / \(c["subject"]!) / \((c["text"] as! String).prefix(30))"

            let (gotHead, gotBody) = split(data)
            let (expHead, expBody) = split(expected)
            XCTAssertEqual(gotBody, expBody, "body: \(label)")

            if c["exact_headers"] as! Bool {
                XCTAssertEqual(String(decoding: gotHead, as: UTF8.self),
                               String(decoding: expHead, as: UTF8.self), "headers: \(label)")
                continue
            }
            let got = headers(gotHead)
            let exp = headers(expHead)
            XCTAssertEqual(got.map(\.0), exp.map(\.0), "header names: \(label)")
            for ((name, value), (_, expValue)) in zip(got, exp) {
                if ["From", "To", "Subject"].contains(name) {
                    XCTAssertEqual(decodeEncodedWords(value), decodeEncodedWords(expValue), "\(name): \(label)")
                } else {
                    XCTAssertEqual(value, expValue, "\(name): \(label)")
                }
            }
            for line in String(decoding: gotHead, as: UTF8.self).split(separator: "\n") {
                XCTAssertTrue(line.unicodeScalars.allSatisfy(\.isASCII), "non-ASCII header: \(line)")
                XCTAssertLessThanOrEqual(line.count, 78, "long header line: \(line)")
            }
        }
    }

    // MARK: - Workspace scenarios

    func testScaffold() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let ws = Workspace(root: root, catalogue: Self.catalogue)
        try ws.ensureScaffold()
        ws.scan()
        assertSnapshot(ws, root: root, fx["scaffold"] as! JSON, "scaffold")
    }

    func testWorkspaceScenarios() throws {
        for case let sc as JSON in list("scenarios") {
            let name = sc["name"] as! String
            let root = try makeTempDir()
            defer { try? FileManager.default.removeItem(at: root) }
            for (rel, content) in sc["files"] as! [String: String] {
                let url = root.appendingPathComponent(rel)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try Data(content.utf8).write(to: url)
            }
            let ws = Workspace(root: root, catalogue: Self.catalogue)
            assertSnapshot(ws, root: root, sc["before"] as! JSON, "\(name) before")

            let expectedResults = sc["results"] as! [Any]
            for (i, op) in (sc["ops"] as! [[Any]]).enumerated() {
                let got = try apply(op, to: ws)
                XCTAssertTrue(sameResult(got, expectedResults[i]),
                              "\(name) op \(i) \(op): got \(String(describing: got)), expected \(expectedResults[i])")
            }
            assertSnapshot(ws, root: root, sc["after"] as! JSON, "\(name) after")
            ws.scan()
            assertSnapshot(ws, root: root, sc["rescanned"] as! JSON, "\(name) rescanned")
        }
    }

    // MARK: - Helpers

    private func apply(_ op: [Any], to ws: Workspace) throws -> Any? {
        let name = op[0] as! String
        let a = op.count > 1 ? op[1] as! String : ""
        switch name {
        case "add_favourite": return try ws.addFavourite(a)
        case "add_custom_favourite": return try ws.addCustomFavourite(a)
        case "remove_favourite": return try ws.removeFavourite(a)
        case "set_favourite_label": try ws.setFavouriteLabel(a, op[2] as! String); return nil
        case "move_favourite": return try ws.moveFavourite(a, by: op[2] as! Int)
        case "add_phrase": let p = try ws.addPhrase(a); return [p.id, p.text]
        case "edit_phrase": try ws.editPhrase(a, text: op[2] as! String); return nil
        case "delete_phrase": try ws.deletePhrase(a); return nil
        case "move_phrase": return try ws.movePhrase(a, by: op[2] as! Int)
        default: XCTFail("unknown op \(name)"); return nil
        }
    }

    private func sameResult(_ got: Any?, _ expected: Any) -> Bool {
        switch (got, expected) {
        case (nil, is NSNull): return true
        case let (g as Bool, e as Bool): return g == e
        case let (g as String, e as String): return g == e
        case let (g as [String], e as [String]): return g == e
        default: return false
        }
    }

    private func assertSnapshot(_ ws: Workspace, root: URL, _ exp: JSON, _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(ws.favouriteIDs, exp["favourite_ids"] as! [String], "\(label): ids", file: file, line: line)
        XCTAssertEqual(ws.favouriteLabels, exp["favourite_labels"] as! [String: String], "\(label): labels", file: file, line: line)
        XCTAssertEqual(ws.favouriteChars, exp["favourite_chars"] as! [String: String], "\(label): chars", file: file, line: line)
        XCTAssertEqual(ws.phrases.map { [$0.id, $0.text] }, exp["phrases"] as! [[String]], "\(label): phrases", file: file, line: line)
        let profiles = (exp["profiles"] as! [[Any]]).map { "\($0[0] as! String)=\(($0[1] as! [String]).joined(separator: "|"))" }
        XCTAssertEqual(ws.profiles.map { "\($0.name)=\($0.lines.joined(separator: "|"))" }, profiles, "\(label): profiles", file: file, line: line)
        XCTAssertEqual(ws.signoff, exp["signoff"] as! String, "\(label): signoff", file: file, line: line)
        XCTAssertEqual(ws.disclaimer, exp["disclaimer"] as! String, "\(label): disclaimer", file: file, line: line)
        XCTAssertEqual(ws.favouriteEmoji().map(\.id), exp["favourite_emoji"] as! [String], "\(label): favourite emoji", file: file, line: line)
        XCTAssertEqual(ws.customFavourites().map { [$0.id, $0.char, $0.name] }, exp["custom_favourites"] as! [[String]], "\(label): customs", file: file, line: line)
        let validate = exp["validate"] as! [String: [String]]
        XCTAssertEqual(ws.validate(), Workspace.Problems(orphanFavourites: validate["orphan_favourites"]!,
                                                         missingFiles: validate["missing_files"]!),
                       "\(label): validate", file: file, line: line)

        let expFiles = (exp["files"] as! [String: String]).mapValues { Data(base64Encoded: $0)! }
        var gotFiles: [String: Data] = [:]
        let prefix = root.standardizedFileURL.path + "/"
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let url as URL in e {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let rel = String(url.standardizedFileURL.path.dropFirst(prefix.count))
                gotFiles[rel] = try? Data(contentsOf: url)
            }
        }
        XCTAssertEqual(gotFiles.keys.sorted(), expFiles.keys.sorted(), "\(label): file list", file: file, line: line)
        for (rel, data) in expFiles {
            XCTAssertEqual(gotFiles[rel].map { String(decoding: $0, as: UTF8.self) },
                           String(decoding: data, as: UTF8.self), "\(label): \(rel)", file: file, line: line)
        }
    }

    private func split(_ data: Data) -> (Data, Data) {
        let bytes = [UInt8](data)
        for i in 0..<(bytes.count - 1) where bytes[i] == 0x0A && bytes[i + 1] == 0x0A {
            return (Data(bytes[...i]), Data(bytes[(i + 2)...]))
        }
        return (data, Data())
    }

    /// Unfolded (name, value) header pairs.
    private func headers(_ head: Data) -> [(String, String)] {
        var out: [(String, String)] = []
        for line in String(decoding: head, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(" ") || line.hasPrefix("\t"), !out.isEmpty {
                out[out.count - 1].1 += line
            } else if let colon = line.firstIndex(of: ":") {
                out.append((String(line[..<colon]), String(line[line.index(after: colon)...])))
            }
        }
        return out.map { ($0.0, $0.1.trimmingCharacters(in: .whitespaces)) }
    }
}

/// Decode RFC 2047 encoded words (UTF-8, "b" or "q"), dropping whitespace
/// between adjacent encoded words, as mail clients do.
func decodeEncodedWords(_ value: String) -> String {
    let regex = try! NSRegularExpression(pattern: "=\\?utf-8\\?([bqBQ])\\?([^?]*)\\?=")
    let ns = value as NSString
    var out = ""
    var cursor = 0
    var previousWasWord = false
    for m in regex.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
        let gap = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
        if !(previousWasWord && gap.trimmingCharacters(in: .whitespaces).isEmpty) { out += gap }
        let kind = ns.substring(with: m.range(at: 1)).lowercased()
        let text = ns.substring(with: m.range(at: 2))
        var bytes: [UInt8] = []
        if kind == "b" {
            bytes = [UInt8](Data(base64Encoded: text) ?? Data())
        } else {
            let chars = Array(text.utf8)
            var i = 0
            while i < chars.count {
                if chars[i] == UInt8(ascii: "_") {
                    bytes.append(0x20)
                } else if chars[i] == UInt8(ascii: "="), i + 2 < chars.count,
                          let b = UInt8(String(decoding: chars[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                    bytes.append(b)
                    i += 2
                } else {
                    bytes.append(chars[i])
                }
                i += 1
            }
        }
        out += String(decoding: bytes, as: UTF8.self)
        cursor = m.range.location + m.range.length
        previousWasWord = true
    }
    out += ns.substring(from: cursor)
    return out
}

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("nicemail-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
