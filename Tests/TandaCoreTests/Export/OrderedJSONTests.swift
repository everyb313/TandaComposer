import XCTest
import Foundation

/// `JSONValue` writes the exported Setlist/Tanda files. Key order, the
/// " : " separator, indentation and escaping are part of the file format,
/// so most tests compare the exact text.
@MainActor
final class OrderedJSONTests: XCTestCase {

    // MARK: - Scalars

    func testScalars() {
        XCTAssertEqual(JSONValue.null.serialized(), "null")
        XCTAssertEqual(JSONValue.bool(true).serialized(), "true")
        XCTAssertEqual(JSONValue.bool(false).serialized(), "false")
        XCTAssertEqual(JSONValue.number("42").serialized(), "42")
        XCTAssertEqual(JSONValue.string("abc").serialized(), "\"abc\"")
    }

    func testNumberLiteralIsWrittenVerbatim() {
        XCTAssertEqual(JSONValue.number("1.50").serialized(), "1.50")
    }

    // MARK: - Optional constructors

    func testOptionalStringAndNil() {
        let some: String? = "x"
        let none: String? = nil

        XCTAssertEqual(JSONValue.opt(some).serialized(), "\"x\"")
        XCTAssertEqual(JSONValue.opt(none).serialized(), "null")
    }

    func testOptionalIntegers() {
        let int: Int? = 5
        let noInt: Int? = nil
        let int64: Int64? = 9_000_000_000
        let noInt64: Int64? = nil

        XCTAssertEqual(JSONValue.opt(int).serialized(), "5")
        XCTAssertEqual(JSONValue.opt(noInt).serialized(), "null")
        XCTAssertEqual(JSONValue.opt(int64).serialized(), "9000000000")
        XCTAssertEqual(JSONValue.opt(noInt64).serialized(), "null")
    }

    func testWholeDoublesHaveNoTrailingZero() {
        let values: [(Double, String)] = [(111.0, "111"), (0.0, "0"), (-3.0, "-3")]

        for (value, expected) in values {
            let optional: Double? = value
            XCTAssertEqual(JSONValue.opt(optional).serialized(), expected)
        }
    }

    func testFractionalDoublesUseShortestRepresentation() {
        let values: [(Double, String)] = [(111.5, "111.5"), (0.1, "0.1"), (-2.25, "-2.25")]

        for (value, expected) in values {
            let optional: Double? = value
            XCTAssertEqual(JSONValue.opt(optional).serialized(), expected)
        }
    }

    func testNilDoubleIsNull() {
        let none: Double? = nil
        XCTAssertEqual(JSONValue.opt(none).serialized(), "null")
    }

    // MARK: - Escaping

    func testStandardEscapes() {
        XCTAssertEqual(JSONValue.string("a\"b").serialized(), "\"a\\\"b\"")
        XCTAssertEqual(JSONValue.string("a\\b").serialized(), "\"a\\\\b\"")
        XCTAssertEqual(JSONValue.string("a\nb").serialized(), "\"a\\nb\"")
        XCTAssertEqual(JSONValue.string("a\rb").serialized(), "\"a\\rb\"")
        XCTAssertEqual(JSONValue.string("a\tb").serialized(), "\"a\\tb\"")
    }

    func testOtherControlCharactersUseLowercaseUnicodeEscapes() {
        XCTAssertEqual(JSONValue.string("\u{01}").serialized(), "\"\\u0001\"")
        XCTAssertEqual(JSONValue.string("\u{1F}").serialized(), "\"\\u001f\"")
    }

    func testForwardSlashIsNotEscaped() {
        let text = JSONValue.string("/Volumes/Music/a.flac").serialized()

        XCTAssertEqual(text, "\"/Volumes/Music/a.flac\"")
        XCTAssertFalse(text.contains("\\/"))
    }

    func testNonASCIICharactersAreKeptAsIs() {
        XCTAssertEqual(JSONValue.string("Caf\u{00E9} \u{1F3B6}").serialized(), "\"Caf\u{00E9} \u{1F3B6}\"")
    }

    func testKeysAreEscapedToo() {
        let text = JSONValue.object([("a\"b", .null)]).serialized()

        XCTAssertEqual(text, "{\n  \"a\\\"b\" : null\n}")
    }

    func testEscapedStringsAreValidJSONThatReadsBackIdentically() throws {
        let original = "a\"b\\c\nd\re\tf/g\u{01}\u{1F}\u{00E9}\u{1F3B6}"
        let text = JSONValue.string(original).serialized()

        let parsed = try JSONSerialization.jsonObject(
            with: Data(text.utf8),
            options: [.fragmentsAllowed]
        ) as? String

        XCTAssertEqual(parsed, original)
    }

    // MARK: - Structure and layout

    func testEmptyContainers() {
        XCTAssertEqual(JSONValue.array([]).serialized(), "[]")
        XCTAssertEqual(JSONValue.object([]).serialized(), "{}")
    }

    func testArrayLayout() {
        let value = JSONValue.array([.number("1"), .number("2")])

        XCTAssertEqual(value.serialized(), "[\n  1,\n  2\n]")
    }

    func testObjectKeepsTheGivenKeyOrder() {
        let value = JSONValue.object([
            ("zebra", .number("1")),
            ("apple", .number("2")),
            ("mango", .number("3"))
        ])

        XCTAssertEqual(
            value.serialized(),
            "{\n  \"zebra\" : 1,\n  \"apple\" : 2,\n  \"mango\" : 3\n}"
        )
    }

    func testNestedLayout() {
        let value = JSONValue.object([
            ("list", .array([.string("x")])),
            ("inner", .object([("k", .null)]))
        ])

        let expected = """
        {
          "list" : [
            "x"
          ],
          "inner" : {
            "k" : null
          }
        }
        """

        XCTAssertEqual(value.serialized(), expected)
    }

    func testObjectInsideArrayLayout() {
        let value = JSONValue.array([.object([("a", .number("1"))])])

        XCTAssertEqual(value.serialized(), "[\n  {\n    \"a\" : 1\n  }\n]")
    }

    func testNoTrailingNewlineIsAdded() {
        XCTAssertFalse(JSONValue.object([("a", .null)]).serialized().hasSuffix("\n"))
    }

    // MARK: - Compatibility

    func testSerializedTreeIsValidJSON() throws {
        let value = JSONValue.object([
            ("title", .string("Poema")),
            ("year", .opt(Optional<Int>(1940))),
            ("bpm", .opt(Optional<Double>(111.0))),
            ("tags", .array([.string("a"), .string("b")])),
            ("missing", .null)
        ])

        let parsed = try JSONSerialization.jsonObject(with: Data(value.serialized().utf8))
        let object = try XCTUnwrap(parsed as? [String: Any])

        XCTAssertEqual(object["title"] as? String, "Poema")
        XCTAssertEqual(object["year"] as? Int, 1940)
        XCTAssertEqual(object["bpm"] as? Int, 111)
        XCTAssertEqual(object["tags"] as? [String], ["a", "b"])
        XCTAssertTrue(object["missing"] is NSNull)
    }

    func testOutputKeepsKeyOrderAfterAParserWouldHaveLostIt() {
        let text = JSONValue.object([("zebra", .null), ("apple", .null)]).serialized()

        let zebra = text.range(of: "\"zebra\"")
        let apple = text.range(of: "\"apple\"")

        XCTAssertNotNil(zebra)
        XCTAssertNotNil(apple)
        if let zebra, let apple {
            XCTAssertLessThan(zebra.lowerBound, apple.lowerBound)
        }
    }

    func testOldEscapedSlashesAreStillValidJSON() throws {
        // Files written by older versions used "\\/"; they must stay readable.
        let old = "\"\\/Volumes\\/Music\""

        let parsed = try JSONSerialization.jsonObject(
            with: Data(old.utf8),
            options: [.fragmentsAllowed]
        ) as? String

        XCTAssertEqual(parsed, "/Volumes/Music")
    }
}
