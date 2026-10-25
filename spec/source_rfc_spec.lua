local rfc = require("rfc.source.rfc")
local fixtures = require("spec.fixtures")

local function section(sections, number, title)
    for _, s in ipairs(sections) do
        if s.number == number and (title == nil or s.title == title) then
            return s
        end
    end
end

describe("contents", function()
    describe("of RFC 9110", function()
        local lines, sections
        before_each(function()
            lines = fixtures.read(fixtures.rfc9110)
            sections = (rfc.contents(lines))
        end)
        it("finds every row", function()
            assert.are.equal(305, #sections)
        end)
        it("reads a numbered row: number, printed label, title, heading line, row line", function()
            assert.are.same(
                { number = "1.1", label = "1.1.", title = "Purpose", line = 382, toc_line = 74 },
                section(sections, "1.1")
            )
            assert.are.equal(697, section(sections, "3.1").line)
        end)
        it("tells 1 from 1.1 by the title", function()
            assert.are.equal(380, section(sections, "1").line)
        end)
        it("reads an appendix row by its letter", function()
            local a = section(sections, "A")
            assert.are.equal("Appendix A.", a.label)
            assert.are.equal(9748, a.line)
            assert.are.equal(9980, section(sections, "B.1").line)
        end)
        it("reads an unnumbered row", function()
            local index = section(sections, "", "Index")
            assert.are.same({ number = "", label = "", title = "Index", line = 10217, toc_line = 377 }, index)
        end)
        it("joins a wrapped row's title and finds its heading", function()
            local s = section(sections, "8.8.3.3")
            assert.are.equal("Example: Entity Tags Varying on Content-Negotiated Resources", s.title)
            assert.are.equal(3672, s.line)
        end)
        it("keeps a title that ends in a number", function()
            assert.are.equal("Changes from RFC 2818", section(sections, "B.1").title)
        end)
    end)

    it("reads dot-leader rows with page numbers (RFC 2616)", function()
        local sections = (rfc.contents(fixtures.read(fixtures.rfc2616)))
        assert.are.equal(253, #sections)
        assert.are.same(
            { number = "1.4", label = "1.4", title = "Overall Operation", line = 628, toc_line = 69 },
            section(sections, "1.4")
        )
        assert.are.equal(5784, section(sections, "14.4").line)
        assert.are.equal(9770, section(sections, "20", "Index").line)
    end)
    it("reads rows with a gap before the page number (RFC 1945)", function()
        local sections = (rfc.contents(fixtures.read(fixtures.rfc1945)))
        assert.are.equal(177, section(sections, "1.1").line)
    end)
    it("reads spaced dot leaders (RFC 3986)", function()
        local sections = (rfc.contents(fixtures.read(fixtures.rfc3986)))
        assert.are.equal(203, section(sections, "1.1").line)
    end)
    it("reads column-0 rows, centred headings and APPENDIX A: rows (RFC 791)", function()
        local sections = (rfc.contents(fixtures.read(fixtures.rfc791)))
        assert.are.equal(18, #sections)
        assert.are.equal(249, section(sections, "1").line)
        assert.are.equal(475, section(sections, "2").line)
        assert.are.same(
            { number = "A", label = "APPENDIX A:", title = "Examples & Scenarios", line = 2186, toc_line = 85 },
            section(sections, "A")
        )
        assert.are.equal(2599, section(sections, "", "GLOSSARY").line)
    end)
    it("skips the running header and footer where the ToC crosses a page", function()
        local sections = (rfc.contents(fixtures.read(fixtures.rfc791)))
        assert.is_nil(section(sections, "", "Internet Protocol"))
        assert.is_nil(section(sections, "", "September 1981"))
    end)
    it("answers no sections for a text without a table of contents", function()
        assert.are.same({}, rfc.contents({ "no contents here", "1. Only a heading" }))
    end)
    it("reads a table of contents on the first line", function()
        local sections = (rfc.contents({ "Table of Contents", "   1. Intro ... 1", "", "1. Intro", "   body" }))
        assert.are.same({ { number = "1", label = "1.", title = "Intro", line = 4, toc_line = 2 } }, sections)
    end)
    it("leaves out a row whose heading never appears", function()
        local sections = (rfc.contents({ "Contents", "   1. Intro", "   2. Missing", "", "1. Intro" }))
        assert.are.equal(1, #sections)
    end)
end)

describe("references", function()
    it("finds the section and every entry's line", function()
        local lines = fixtures.read(fixtures.rfc9110)
        local refs = rfc.references(lines, (rfc.contents(lines)))
        assert.are.equal(9355, refs.line)
        assert.are.equal(9359, refs.entries["[CACHING]"])
        assert.are.equal(9583, refs.entries["[RFC2616]"])
    end)
    it("is empty for a text with no references", function()
        local lines = fixtures.read(fixtures.rfc791)
        assert.are.same({ entries = {} }, rfc.references(lines, (rfc.contents(lines))))
    end)
end)

describe("cited_rfc", function()
    it("reads the RFC an entry cites, within its block", function()
        local lines = fixtures.read(fixtures.rfc9110)
        assert.are.equal("9111", rfc.cited_rfc(lines, 9359))
    end)
    it("answers nil when the block names no RFC", function()
        assert.is_nil(rfc.cited_rfc({ "   [X]  Nobody, 2020.", "", "   RFC 1" }, 1))
    end)
end)

describe("mentions", function()
    it("finds bracketed and bare RFC mentions with the span a link replaces", function()
        assert.are.same({
            { kind = "rfc", first = 4, last = 12, rfc = "2068" },
            { kind = "rfc", first = 31, last = 39, rfc = "2616" },
        }, rfc.mentions("   [RFC2068], revised in 1999 [RFC2616], and"))
        assert.are.same(
            { { kind = "rfc", first = 1, last = 8, rfc = "9110" } },
            rfc.mentions("RFC 9110  HTTP Semantics")
        )
        assert.are.same({ { kind = "rfc", first = 5, last = 11, rfc = "2616" } }, rfc.mentions("see RFC2616 too"))
    end)
    it("finds a section of this document, the span being its number", function()
        assert.are.same(
            { { kind = "section", first = 13, last = 15, number = "3.1" } },
            rfc.mentions("   (Section 3.1) -- regardless")
        )
    end)
    it("drops a section number's trailing dot from the span", function()
        assert.are.same({ { kind = "section", first = 9, last = 11, number = "3.1" } }, rfc.mentions("Section 3.1."))
    end)
    it("names the RFC a section is of, bracketed or bare", function()
        assert.are.same({
            { kind = "section", first = 9, last = 12, number = "14.4", rfc = "2616" },
            { kind = "rfc", first = 17, last = 25, rfc = "2616" },
        }, rfc.mentions("Section 14.4 of [RFC2616]."))
        assert.are.same({
            { kind = "section", first = 9, last = 9, number = "2", rfc = "7841" },
            { kind = "rfc", first = 14, last = 21, rfc = "7841" },
        }, rfc.mentions("Section 2 of RFC 7841"))
    end)
    it("names the citation a section is of", function()
        assert.are.same({
            { kind = "section", first = 9, last = 11, number = "4.2", citation = "[CACHING]" },
            { kind = "citation", first = 16, last = 24, citation = "[CACHING]" },
        }, rfc.mentions("Section 4.2 of [CACHING]"))
    end)
    it("finds citations", function()
        assert.are.same({
            { kind = "citation", first = 4, last = 12, citation = "[CACHING]" },
            { kind = "citation", first = 30, last = 39, citation = "[HTTP/1.1]" },
        }, rfc.mentions('   [CACHING], and "HTTP/1.1" [HTTP/1.1].'))
    end)
    it("finds nothing in plain text", function()
        assert.are.same({}, rfc.mentions("   The target of an HTTP request is called a resource."))
    end)
end)

describe("blocks", function()
    it("classifies every line of RFC 9110 and carries its mentions", function()
        local lines = fixtures.read(fixtures.rfc9110)
        local blocks = rfc.blocks(lines)
        assert.are.equal(#lines, #blocks)
        assert.are.equal("heading", blocks[382].kind)
        assert.are.equal("1.1", blocks[382].section.number)
        assert.are.equal("row", blocks[74].kind)
        assert.are.equal(382, blocks[74].section.line)
        assert.are.equal("reference", blocks[9359].kind)
        assert.are.equal("[CACHING]", blocks[9359].citation)
        assert.are.equal("line", blocks[435].kind)
        assert.are.equal("2616", blocks[435].mentions[2].rfc)
        assert.are.equal(lines[435], blocks[435].text)
    end)
    it("leaves a page header without mentions", function()
        local blocks = rfc.blocks(fixtures.read(fixtures.rfc2616))
        assert.are.equal("header", blocks[60].kind)
        assert.are.same({}, blocks[60].mentions)
    end)
    it("reads a text without a table of contents as lines", function()
        local blocks = rfc.blocks({ "see RFC 7841 for more" })
        assert.are.equal("line", blocks[1].kind)
        assert.are.equal("7841", blocks[1].mentions[1].rfc)
    end)
end)

describe("index", function()
    local entries
    before_each(function()
        entries = rfc.index(fixtures.read(fixtures.rfc_index))
    end)
    it("reads the numbered blocks and leaves out Not Issued numbers", function()
        assert.are.equal(4, #entries)
        assert.is_nil(fixtures.find(entries, "number", "14"))
    end)
    it("reads an entry's label, obsoletes, obsoleted_by, formats and status", function()
        assert.are.same({
            number = "266",
            label = "Network host status. E. Westheimer. November 1971.",
            obsoletes = "RFC255",
            obsoleted_by = "RFC267",
            formats = { "TXT", "HTML" },
            status = "UNKNOWN",
        }, fixtures.find(entries, "number", "266"))
        assert.are.equal("DRAFT STANDARD", fixtures.find(entries, "number", "2616").status)
    end)
    it("joins a block wrapped over lines", function()
        local e = fixtures.find(entries, "number", "61")
        assert.are.equal(
            "Note on Interprocess Communication in a Resource Sharing Computer Network. D.C. Walden. July 1970.",
            e.label
        )
        assert.are.equal("RFC62", e.obsoleted_by)
        assert.is_nil(e.obsoletes)
        assert.are.equal(
            "Binary Message Forms in Computer. D. Bobrow, W.R. Sutherland. February 1968.",
            fixtures.find(entries, "number", "31").label
        )
    end)
    it("reads a list of obsoleting RFCs and several formats", function()
        local e = fixtures.find(entries, "number", "2616")
        assert.are.equal("RFC7230, RFC7231, RFC7232, RFC7233, RFC7234, RFC7235", e.obsoleted_by)
        assert.are.same({ "TXT", "PS", "PDF", "HTML" }, e.formats)
    end)
end)
