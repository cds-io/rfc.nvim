local outline = require("rfc.outline")
local help = require("rfc.help")
local help_eip = require("rfc.help_eip")
local fixtures = require("spec.fixtures")

local function render(fixture, id)
    return help.render(id, fixtures.read(fixture)).lines
end

describe("outline.of", function()
    describe("over RFC 9110", function()
        local headings
        before_each(function()
            headings = outline.of(render(fixtures.rfc9110, "9110"))
        end)
        it("lists every section heading with its tag, text, level and line", function()
            assert.are.equal(305, #headings)
            assert.are.same({ tag = "rfc9110-1", text = "1.  Introduction", level = 1, line = 381 }, headings[1])
            assert.are.same({ tag = "rfc9110-1.1", text = "1.1.  Purpose", level = 2, line = 383 }, headings[2])
            assert.are.same(
                { tag = "rfc9110-authors-addresses", text = "Authors' Addresses", level = 1, line = 10761 },
                headings[305]
            )
        end)
        it("takes a numbered heading's level from its number", function()
            local function find(text)
                for _, h in ipairs(headings) do
                    if h.text == text then
                        return h
                    end
                end
            end
            assert.are.same(
                { tag = "rfc9110-5.6.1.1", text = "5.6.1.1.  Sender Requirements", level = 4, line = 1675 },
                find("5.6.1.1.  Sender Requirements")
            )
            assert.are.same(
                { tag = "rfc9110-A", text = "Appendix A.  Collected ABNF", level = 1, line = 9749 },
                find("Appendix A.  Collected ABNF")
            )
            assert.are.same(
                { tag = "rfc9110-B.1", text = "B.1.  Changes from |rfc2818|", level = 2, line = 9981 },
                find("B.1.  Changes from |rfc2818|")
            )
            assert.are.same({ tag = "rfc9110-index", text = "Index", level = 1, line = 10218 }, find("Index"))
        end)
        it("leaves the file tags and the reference entries out", function()
            for _, h in ipairs(headings) do
                assert.is_true(h.line > 1)
                assert.is_nil(h.tag:match("%-ref%-"))
            end
        end)
    end)

    it("reads a heading whose number has no trailing dot", function()
        local headings = outline.of(render(fixtures.rfc2616, "2616"))
        assert.are.same({ tag = "rfc2616-1", text = "1 Introduction", level = 1, line = 360 }, headings[1])
        assert.are.same({ tag = "rfc2616-1.1", text = "1.1 Purpose", level = 2, line = 362 }, headings[2])
    end)

    it("takes an unnumbered heading's level from its row in the contents", function()
        local headings = outline.of(help_eip.render("1559", fixtures.read(fixtures.eip1559)).lines)
        assert.are.equal(13, #headings)
        assert.are.same({ tag = "eip1559-abstract", text = "ABSTRACT", level = 1, line = 25 }, headings[2])
        assert.are.same(
            { tag = "eip1559-block-hash-changing", text = "Block Hash Changing", level = 2, line = 316 },
            headings[6]
        )
        -- written in capitals by its author, a level below Backwards Compatibility all the same
        assert.are.same({ tag = "eip1559-gasprice", text = "GASPRICE", level = 2, line = 319 }, headings[7])
    end)

    it("measures an unnumbered heading's level from the shallowest row", function()
        -- every heading of this proposal is a level-three heading in its markdown
        local headings = outline.of(help_eip.render("1123", fixtures.read(fixtures.erc1123)).lines)
        local by_tag = {}
        for _, h in ipairs(headings) do
            by_tag[h.tag] = h
        end
        assert.are.equal(1, by_tag["eip1123-rfc2119"].level)
        assert.are.equal(2, by_tag["eip1123-format"].level)
    end)

    it("reads a heading tagged with a four-letter prefix", function()
        local headings = outline.of({
            "*simd64.txt*  T  *simd64*",
            "CONTENTS",
            "  |simd64-summary|  Summary",
            "",
            "SUMMARY   *simd64-summary*",
        })
        assert.are.same({ { tag = "simd64-summary", text = "SUMMARY", level = 1, line = 5 } }, headings)
    end)

    it("answers no headings for a document without section tags", function()
        assert.are.same({}, outline.of({ "*rfc1.txt*  Nothing  *rfc1*", "", "text" }))
    end)
end)

describe("outline.of over a subjects document", function()
    it("takes a heading's level from the contents block, never from its text", function()
        local headings = outline.of({
            "*rfc-subjects.txt*  RFCs by subject  *rfc-subjects*",
            "",
            "|rfc-subjects-iot|  IoT (0)",
            "  |rfc-subjects-iot-6lowpan|  6LoWPAN (2)",
            "",
            "IoT  (0)  *rfc-subjects-iot*",
            "",
            "IoT / 6LoWPAN  (2)  *rfc-subjects-iot-6lowpan*",
            "|rfc4944|  Transmission of IPv6 Packets over IEEE 802.15.4 Networks (2007)",
        })
        assert.are.same({
            { tag = "rfc-subjects-iot", text = "IoT  (0)", level = 1, line = 6 },
            { tag = "rfc-subjects-iot-6lowpan", text = "IoT / 6LoWPAN  (2)", level = 2, line = 8 },
        }, headings)
    end)
end)

describe("outline.at", function()
    local headings
    before_each(function()
        headings = outline.of(render(fixtures.rfc9110, "9110"))
    end)
    it("is nil above the first heading", function()
        assert.is_nil(outline.at(headings, 1))
        assert.is_nil(outline.at(headings, 380))
    end)
    it("is the heading on the line and the one above any other line", function()
        assert.are.equal(1, outline.at(headings, 381))
        assert.are.equal(1, outline.at(headings, 382))
        assert.are.equal(2, outline.at(headings, 383))
        assert.are.equal(305, outline.at(headings, 10785))
    end)
end)

describe("outline.step", function()
    local headings
    before_each(function()
        headings = outline.of(render(fixtures.rfc9110, "9110"))
    end)
    it("goes forward to the count-th heading after the line", function()
        assert.are.equal(1, outline.step(headings, 1, 1))
        assert.are.equal(2, outline.step(headings, 381, 1))
        assert.are.equal(2, outline.step(headings, 382, 1))
        assert.are.equal(4, outline.step(headings, 382, 3))
    end)
    it("goes back to the count-th heading before the line", function()
        assert.are.equal(1, outline.step(headings, 383, -1))
        assert.are.equal(1, outline.step(headings, 382, -1))
        assert.are.equal(2, outline.step(headings, 456, -2))
    end)
    it("stops at the ends", function()
        assert.are.equal(305, outline.step(headings, 1, 400))
        assert.are.equal(1, outline.step(headings, 10785, -400))
    end)
    it("is nil with no heading in that direction", function()
        assert.is_nil(outline.step(headings, 381, -1))
        assert.is_nil(outline.step(headings, 10761, 1))
        assert.is_nil(outline.step(headings, 500, 0))
    end)
end)

describe("outline.rows", function()
    it("indents each heading by its level and spans its number", function()
        local rows = outline.rows({
            { tag = "rfc9110-1", text = "1.  Introduction", level = 1, line = 381 },
            { tag = "rfc9110-1.1", text = "1.1.  Purpose", level = 2, line = 383 },
            { tag = "rfc9110-5.6.1.1", text = "5.6.1.1.  Sender Requirements", level = 4, line = 1675 },
            { tag = "rfc9110-A", text = "Appendix A.  Collected ABNF", level = 1, line = 9749 },
            { tag = "rfc9110-index", text = "Index", level = 1, line = 10218 },
            { tag = "rfc2616-1", text = "1 Introduction", level = 1, line = 360 },
        })
        assert.are.same({
            "1.  Introduction",
            "  1.1.  Purpose",
            "      5.6.1.1.  Sender Requirements",
            "Appendix A.  Collected ABNF",
            "Index",
            "1 Introduction",
        }, rows.lines)
        assert.are.same({ 0, 2 }, rows.labels[1])
        assert.are.same({ 2, 6 }, rows.labels[2])
        assert.are.same({ 6, 14 }, rows.labels[3])
        assert.are.same({ 0, 11 }, rows.labels[4])
        assert.is_nil(rows.labels[5])
        assert.are.same({ 0, 1 }, rows.labels[6])
    end)
end)
