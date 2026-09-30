import Foundation
import XCTest
@testable import NiceMailCore

/// Behaviour that isn't covered by the Python fixtures: the deliberate
/// differences listed in docs/MAINTENANCE.md §4, and the helpers.
final class CoreTests: XCTestCase {
    private static let catalogue = EmojiCatalogue()

    // MARK: - Text helpers

    func testPythonStringHelpers() {
        XCTAssertEqual("\u{1C} \u{A0}x y\u{3000}\n".pyStrip, "x y")
        XCTAssertEqual("a\r\nb\rc\nd\u{2028}e\n".pySplitLines, ["a", "b", "c", "d", "e"])
        XCTAssertEqual("a\n\nb".pySplitLines, ["a", "", "b"])
        XCTAssertEqual("".pySplitLines, [])
        XCTAssertEqual("a\r\nb\rc".universalNewlines, "a\nb\nc")
        XCTAssertEqual("x\n\n".pyRStrip(["\n"]), "x")
        XCTAssertEqual("🇬🇧abc".pyPrefix(2), "🇬🇧")
        XCTAssertTrue(codePointPrecedes("Zeta", "alpha"))
    }

    func testMessageRefUsesUnambiguousAlphabet() {
        for _ in 0..<200 {
            let ref = Naming.generateMessageRef()
            XCTAssertEqual(ref.count, Naming.messageRefLength)
            XCTAssertTrue(ref.allSatisfy { Naming.messageRefAlphabet.contains($0) }, ref)
        }
    }

    // MARK: - CSV

    func testCSVRoundTrip() {
        let rows = [["id", "text"], ["1", "Hello, \"world\"\nline two"], ["2", ""], ["3", " padded "]]
        let text = CSV.format(rows)
        XCTAssertEqual(text, "id,text\r\n1,\"Hello, \"\"world\"\"\nline two\"\r\n2,\r\n3, padded \r\n")
        XCTAssertEqual(CSV.parse(text), rows)
    }

    func testCSVLoneEmptyFieldIsQuoted() {
        XCTAssertEqual(CSV.format([[""]]), "\"\"\r\n")
    }

    func testCSVHeaderMissingColumnsAndBOM() {
        let rows = CSV.parseWithHeader("\u{FEFF}id,label,char\r\nwaving_hand_sign\r\n\r\nx,y,z,extra\r\n")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["id"], "waving_hand_sign")
        XCTAssertNil(rows[0]["label"])
        XCTAssertEqual(rows[1]["char"], "z")
    }

    func testCSVNonStrictQuotes() {
        // Text after a closing quote joins the field, as in Python.
        XCTAssertEqual(CSV.parse("\"ab\"cd,e\n"), [["abcd", "e"]])
        // An unterminated quoted field runs to the end of the data.
        XCTAssertEqual(CSV.parse("a,\"b\nc"), [["a", "b\nc"]])
    }

    // MARK: - Workspace (Mac-specific)

    func testHiddenProfileFilesAreIgnored() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let profiles = root.appendingPathComponent("mailsigs/profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        try Data().write(to: profiles.appendingPathComponent(".DS_Store"))
        try Data("junk".utf8).write(to: profiles.appendingPathComponent("._default.txt"))

        let ws = Workspace(root: root, catalogue: Self.catalogue)
        try ws.ensureScaffold()
        ws.scan()
        // .DS_Store didn't stop the default profile being created, and the
        // AppleDouble file isn't shown as a profile.
        XCTAssertEqual(ws.profiles.map(\.name), ["default"])
        XCTAssertEqual(ws.profile(named: "missing")?.name, "default")
        XCTAssertEqual(ws.profile(named: nil)?.name, "default")
    }

    func testFavouritesWithBOMStillLoad() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("\u{FEFF}id,label,char\r\nwaving_hand_sign,hi,\r\n".utf8)
            .write(to: root.appendingPathComponent("favourite_emoji.csv"))
        let ws = Workspace(root: root, catalogue: Self.catalogue)
        XCTAssertEqual(ws.favouriteIDs, ["waving_hand_sign"])
        XCTAssertEqual(ws.favouriteLabel("waving_hand_sign"), "hi")
    }

    func testSignatureFromWorkspace() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let ws = Workspace(root: root, catalogue: Self.catalogue)
        try ws.ensureScaffold()
        ws.scan()
        let sig = Signature.assemble(signoff: ws.signoff, profile: ws.profile(named: nil),
                                     disclaimer: ws.disclaimer, includeDisclaimer: true,
                                     messageRef: "YyM4mRnjHQ")
        XCTAssertEqual(sig, """
            Kind regards,

            John Smith


            \u{2014}

            John Smith
            Specialist and Superhero
            Data by day, defeating villains by night

            Disclaimer: a disclaimer text goes here

            Message ref. YyM4mRnjHQ

            """)
    }

    /// The bundled sample workspace (read only, never modified here).
    func testSampleWorkspaceLoads() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("sample-workspace", isDirectory: true)
        let ws = Workspace(root: root, catalogue: Self.catalogue)
        XCTAssertEqual(ws.favouriteEmoji().map(\.char), ["\u{1F60A}"])
        XCTAssertEqual(ws.phrases.map(\.id), ["thanks", "follow_up"])
        XCTAssertEqual(ws.profiles.map(\.name), ["default", "support"])
        XCTAssertEqual(ws.validate(), Workspace.Problems())
    }

    // MARK: - EML

    func testEMLNonASCIISubjectDecodesAndFolds() {
        let subject = "Réunion de l’équipe ☕ " + String(repeating: "très long ", count: 12)
        let data = Note.buildEML(address: "Jöhn <me@example.com>", subject: subject, text: "Hi",
                                 messageRef: "ABCDEFGHJK",
                                 date: Date(timeIntervalSince1970: 1_790_000_000),
                                 timeZone: TimeZone(secondsFromGMT: 0)!)
        let text = String(decoding: data, as: UTF8.self)
        let head = text.components(separatedBy: "\n\n")[0]
        for line in head.split(separator: "\n") {
            XCTAssertLessThanOrEqual(line.count, 78, String(line))
            XCTAssertTrue(line.unicodeScalars.allSatisfy(\.isASCII), String(line))
        }
        let unfolded = head.replacingOccurrences(of: "\n ", with: " ")
        let subjectLine = unfolded.split(separator: "\n").first { $0.hasPrefix("Subject:") }!
        XCTAssertEqual(decodeEncodedWords(String(subjectLine.dropFirst("Subject: ".count))), subject.pyStrip)
        let fromLine = unfolded.split(separator: "\n").first { $0.hasPrefix("From:") }!
        XCTAssertEqual(decodeEncodedWords(String(fromLine.dropFirst("From: ".count))), "Jöhn <me@example.com>")
        XCTAssertTrue(text.hasSuffix("Hi\n\n\n\u{2014}\n\nMessage ref. ABCDEFGHJK\n"))
    }

    func testRFC5322DateOffsets() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(Note.rfc5322Date(date, timeZone: TimeZone(secondsFromGMT: 0)!),
                       "Thu, 01 Jan 1970 00:00:00 +0000")
        XCTAssertEqual(Note.rfc5322Date(date, timeZone: TimeZone(secondsFromGMT: -(3 * 3600 + 30 * 60))!),
                       "Wed, 31 Dec 1969 20:30:00 -0330")
    }

    func testQuotedPrintableKeepsEscapesWhole() {
        // A long line of "=" signs must never split an "=3D" escape.
        let qp = Note.quotedPrintable(Array(String(repeating: "=", count: 100).utf8), maxLineLength: 78)
        for line in String(decoding: qp, as: UTF8.self).split(separator: "\n") {
            XCTAssertLessThanOrEqual(line.count, 78)
            let body = line.hasSuffix("=") && line.count % 3 == 1 ? line.dropLast() : line[...]
            XCTAssertEqual(body.count % 3, 0, String(line))
        }
    }
}
