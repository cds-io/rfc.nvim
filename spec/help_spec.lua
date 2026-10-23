local help = require("rfc.help")
local fixtures = require("spec.fixtures")

local function ends_with(s, suffix)
    return s:sub(-#suffix) == suffix
end

describe("tag", function()
    it("names a numbered section by its number", function()
        assert.are.equal("rfc9110-3.1", help.tag("9110", "3.1", "Resources"))
        assert.are.equal("rfc2616-1.4", help.tag("2616", "1.4", "Overall Operation"))
    end)
    it("names an appendix by its letter", function()
        assert.are.equal("rfc9110-A", help.tag("9110", "A", "Collected ABNF"))
        assert.are.equal("rfc9110-B.1", help.tag("9110", "B.1", "Changes from RFC 2818"))
    end)
    it("names an unnumbered row by its slugged title", function()
        assert.are.equal("rfc9110-index", help.tag("9110", "", "Index"))
        assert.are.equal("rfc9110-authors-addresses", help.tag("9110", "", "Authors' Addresses"))
    end)
end)

describe("ref_tag", function()
    it("keeps the citation's case and swaps its punctuation for dashes", function()
        assert.are.equal("rfc9110-ref-CACHING", help.ref_tag("9110", "[CACHING]"))
        assert.are.equal("rfc9110-ref-HTTP-1.1", help.ref_tag("9110", "[HTTP/1.1]"))
    end)
end)

describe("title", function()
    it("reads the centred title after the header block", function()
        assert.are.equal("HTTP Semantics", help.title(fixtures.read(fixtures.rfc9110)))
        assert.are.equal("Hypertext Transfer Protocol -- HTTP/1.1", help.title(fixtures.read(fixtures.rfc2616)))
    end)
    it("reads an old-format title past lines of whitespace", function()
        assert.are.equal("INTERNET PROTOCOL", help.title(fixtures.read(fixtures.rfc791)))
    end)
    it("joins a title wrapped over two lines", function()
        assert.are.equal(
            "A Long Title Continued",
            help.title({
                "Network Working Group    X. Author",
                "Request for Comments: 1",
                "",
                "   A Long Title",
                "   Continued",
                "",
                "Abstract",
            })
        )
    end)
    it("answers nil for text with no title", function()
        assert.is_nil(help.title({}))
        assert.is_nil(help.title({ "only a header line" }))
    end)
end)

describe("clean", function()
    it("drops the byte-order mark, form feeds, carriage returns and the final newline", function()
        assert.are.same({ "a", "b", "", "c" }, help.clean("\239\187\191a\r\nb\f\n\nc\n"))
    end)
    it("answers one empty line for an empty body", function()
        assert.are.same({ "" }, help.clean(""))
    end)
end)

describe("tags_in", function()
    it("reads a tag of a three- or four-letter prefix and a number, and nothing else", function()
        local lines = { "*rfc9110.txt*  T  *rfc9110*", "SUMMARY   *simd64-summary*", "a */* range and *note* words" }
        assert.are.same({
            { name = "rfc9110.txt", line = 1 },
            { name = "rfc9110", line = 1 },
            { name = "simd64-summary", line = 2 },
        }, help.tags_in(lines))
    end)
    it("reads a subjects tag, file and node alike", function()
        local lines = {
            "*rfc-subjects.txt*  RFCs by subject  *rfc-subjects*",
            "web / HTTP  (3)   *rfc-subjects-web-http*",
            "IoT / 6LoWPAN  (2)  *rfc-subjects-iot-6lowpan*",
            "X.509  *rfc-subjects-security-pki-x.509*",
        }
        assert.are.same({
            { name = "rfc-subjects.txt", line = 1 },
            { name = "rfc-subjects", line = 1 },
            { name = "rfc-subjects-web-http", line = 2 },
            { name = "rfc-subjects-iot-6lowpan", line = 3 },
            { name = "rfc-subjects-security-pki-x.509", line = 4 },
        }, help.tags_in(lines))
    end)
end)

describe("section_tag and row_tag", function()
    it("takes a node tag as a section and the file tag as none", function()
        assert.are.equal("rfc-subjects-web-http", help.section_tag("web / HTTP  (3)   *rfc-subjects-web-http*"))
        assert.is_nil(help.section_tag("*rfc-subjects.txt*  RFCs by subject  *rfc-subjects*"))
        assert.are.equal("rfc9110-3.1", help.section_tag("3.1.  Resources  *rfc9110-3.1*"))
        assert.is_nil(help.section_tag("[CACHING]  *rfc9110-ref-CACHING*"))
    end)
    it("reads a contents row's indent and tag", function()
        assert.are.same({ "  ", "rfc-subjects-web-http" }, { help.row_tag("  |rfc-subjects-web-http|  HTTP (3)") })
        assert.are.same({ "", "eip1559-abstract" }, { help.row_tag("|eip1559-abstract|  Abstract") })
        assert.is_nil(help.row_tag("|rfc9110|  HTTP Semantics (2022)"))
    end)
end)

describe("render", function()
    describe("of RFC 9110", function()
        local doc, lines
        before_each(function()
            lines = fixtures.read(fixtures.rfc9110)
            doc = help.render("9110", lines)
        end)
        it("opens with the file tag line and closes with the modeline", function()
            assert.are.equal("*rfc9110.txt*  HTTP Semantics", doc.lines[1]:match("^(.-)%s+%*rfc9110%*$"))
            assert.are.equal(78, #doc.lines[1])
            assert.are.equal(#lines + 4, #doc.lines)
            assert.are.equal("", doc.lines[#doc.lines - 2])
            assert.are.equal(" vim:tw=78:ts=8:ft=help:norl:", doc.lines[#doc.lines - 1])
            assert.are.equal(" rfc.nvim render 5", doc.lines[#doc.lines])
            assert.are.equal(5, help.render_of(doc.lines))
        end)
        it("tags each heading at column 78", function()
            assert.are.equal("1.1.  Purpose", doc.lines[383]:match("^(.-)%s+%*rfc9110%-1%.1%*$"))
            assert.are.equal(78, #doc.lines[383])
            assert.is_true(ends_with(doc.lines[9749], "*rfc9110-A*"))
            assert.is_true(ends_with(doc.lines[10218], "*rfc9110-index*"))
        end)
        it("turns each ToC row's number into a link to its heading", function()
            assert.are.equal("     |rfc9110-1.1|  Purpose", doc.lines[75])
            assert.is_truthy(doc.lines[366]:find("|rfc9110-A|  Collected ABNF", 1, true))
            assert.are.equal("   |rfc9110-index|", doc.lines[378])
        end)
        it("links RFC citations and mentions", function()
            assert.are.equal("   |rfc2068|, revised in 1999 |rfc2616|, and revised again in 2014", doc.lines[436])
        end)
        it("links a section of this RFC when its heading is known", function()
            assert.are.equal(
                "   (Section |rfc9110-3.1|) -- regardless of its type, nature, or implementation --",
                doc.lines[459]
            )
        end)
        it("links a section of a cited RFC to that RFC's tag", function()
            assert.are.equal(
                "   was previously defined for HTTP in Section |rfc2616-14.4| of |rfc2616|.",
                doc.lines[5648]
            )
        end)
        it("links an RFC named on a ToC row or a heading, beside the row link or the tag", function()
            assert.are.equal("     |rfc9110-B.1|  Changes from |rfc2818|", doc.lines[368])
            assert.are.equal("B.1.  Changes from |rfc2818|", doc.lines[9981]:match("^(.-)%s+%*rfc9110%-B%.1%*$"))
        end)
        it("links a named citation to its entry in the references, and tags the entry", function()
            assert.are.equal('   |rfc9110-ref-CACHING|, and "HTTP/1.1" |rfc9110-ref-HTTP-1.1|.', doc.lines[674])
            assert.are.equal(
                "   [CACHING]  Fielding, R., Ed., Nottingham, M., Ed., and J. Reschke,",
                doc.lines[9360]:match("^(.-)%s+%*rfc9110%-ref%-CACHING%*$")
            )
        end)
        it("lists the file, every heading and every named reference as tags", function()
            local by_name = {}
            for _, t in ipairs(doc.tags) do
                by_name[t.name] = t.line
            end
            assert.are.equal(1, by_name["rfc9110"])
            assert.are.equal(1, by_name["rfc9110.txt"])
            assert.are.equal(383, by_name["rfc9110-1.1"])
            assert.are.equal(9360, by_name["rfc9110-ref-CACHING"])
            assert.is_nil(by_name["rfc9110-ref-RFC2616"])
            for _, t in ipairs(doc.tags) do
                assert.is_truthy(doc.lines[t.line]:find("*" .. t.name .. "*", 1, true), t.name)
            end
        end)
    end)

    describe("of other formats", function()
        it("links the RFC a reference entry names on its own line, beside the entry's tag", function()
            local doc = help.render("2616", fixtures.read(fixtures.rfc2616))
            local line = doc.lines[8841]
            assert.is_truthy(line:match('^   %[11%] Fielding, R%., "Relative Uniform Resource Locators", |rfc1808|,'))
            assert.is_truthy(line:match("%*rfc2616%-ref%-11%*$"))
        end)
        it("links the dot-leader rows and tags the headings of RFC 2616", function()
            local doc = help.render("2616", fixtures.read(fixtures.rfc2616))
            assert.is_truthy(doc.lines[70]:find("   |rfc2616-1.4|   Overall Operation", 1, true))
            assert.is_true(ends_with(doc.lines[629], "*rfc2616-1.4*"))
        end)
        it("leaves a page header's RFC number as text", function()
            local doc =
                help.render("2616", { "RFC 2616                        HTTP/1.1                       June 1999" })
            assert.are.equal("RFC 2616                        HTTP/1.1                       June 1999", doc.lines[2])
        end)
        it("tags the indented headings of RFC 791", function()
            local doc = help.render("791", fixtures.read(fixtures.rfc791))
            assert.is_truthy(doc.lines[73]:find("|rfc791-2|", 1, true))
            assert.is_true(ends_with(doc.lines[476], "*rfc791-2*"))
        end)
        it("leaves a same-document section unlinked when no heading was found", function()
            local doc = help.render("1", { "see Section 9.9 for more" })
            assert.are.equal("see Section 9.9 for more", doc.lines[2])
        end)
        it("still links a cross-RFC section without a ToC", function()
            local doc = help.render("1", { "see Section 2 of RFC 7841 for more" })
            assert.are.equal("see Section |rfc7841-2| of |rfc7841| for more", doc.lines[2])
        end)
    end)

    describe("totality", function()
        it("renders empty text", function()
            local doc = help.render("1", {})
            assert.are.same({
                "*rfc1.txt*  RFC 1" .. string.rep(" ", 78 - #"*rfc1.txt*  RFC 1" - #"*rfc1*") .. "*rfc1*",
                "",
                " vim:tw=78:ts=8:ft=help:norl:",
                " rfc.nvim render 5",
            }, doc.lines)
            assert.are.equal(2, #doc.tags)
        end)
        it("renders text whose table of contents sits on the first line", function()
            local doc = help.render("1", { "Table of Contents", "   1. Intro ... 1", "", "1. Intro", "   body" })
            assert.are.equal("   |rfc1-1| Intro ... 1", doc.lines[3])
            assert.is_true(ends_with(doc.lines[5], "*rfc1-1*"))
        end)
    end)
end)

describe("render_of", function()
    it("reads the version from the last line, 0 when there is none", function()
        assert.are.equal(5, help.render_of({ "x", " rfc.nvim render 5" }))
        assert.are.equal(7, help.render_of({ " rfc.nvim render 7" }))
        assert.are.equal(0, help.render_of({ "x", " vim:ft=help:" }))
        assert.are.equal(0, help.render_of({}))
    end)
end)

describe("tags_in", function()
    it("reads back exactly the tags render declared", function()
        local doc = help.render("9110", fixtures.read(fixtures.rfc9110))
        local names = {}
        for _, t in ipairs(help.tags_in(doc.lines)) do
            table.insert(names, t.name)
        end
        local declared = {}
        for _, t in ipairs(doc.tags) do
            table.insert(declared, t.name)
        end
        table.sort(names)
        table.sort(declared)
        assert.are.same(declared, names)
    end)
    it("ignores stars inside the text", function()
        assert.are.same({}, help.tags_in({ "   Accept: */* and *bold*", "*other.txt*" }))
    end)
end)

describe("tags_file", function()
    it("writes one sorted line per tag with the search command between stars", function()
        local lines = help.tags_file({
            { file = "rfcb.txt", tags = { { name = "rfcb", line = 1 } } },
            { file = "rfca.txt", tags = { { name = "rfca-2", line = 3 }, { name = "rfca", line = 1 } } },
        })
        assert.are.same({
            "rfca\trfca.txt\t/*rfca*",
            "rfca-2\trfca.txt\t/*rfca-2*",
            "rfcb\trfcb.txt\t/*rfcb*",
        }, lines)
    end)
end)
