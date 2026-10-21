local help_simd = require("rfc.help_simd")
local help = require("rfc.help")
local fixtures = require("spec.fixtures")

local function find(lines, pattern)
    for i, line in ipairs(lines) do
        if line:match(pattern) then
            return i, line
        end
    end
end

describe("render", function()
    describe("of SIMD-0064", function()
        local doc
        before_each(function()
            doc = help_simd.render("64", fixtures.read(fixtures.simd64))
        end)
        it("opens with the file tag line and the header from the frontmatter", function()
            assert.are.equal("*simd64.txt*  Transaction Receipts", doc.lines[1]:match("^(.-)%s+%*simd64%*$"))
            assert.are.equal(78, #doc.lines[1])
            assert.are.equal(
                "SIMD-0064  Category: Standard  Type: Core  Status: Stagnant  Created: 2023-06-20",
                doc.lines[2]
            )
            assert.are.equal("Feature: N/A", doc.lines[3])
            assert.are.equal(
                "Authors: Anoushk Kharangate (Tinydancer), Richard Patel (Jump), Harsh Patel (Tinydancer)",
                doc.lines[4]
            )
            assert.are.equal("", doc.lines[5])
            assert.are.equal(help.MODELINE, doc.lines[#doc.lines - 1])
            assert.are.equal(help.FOOTER, doc.lines[#doc.lines])
        end)
        it("lists the headings as a table of contents of links", function()
            assert.are.equal("CONTENTS", doc.lines[6])
            assert.are.equal("  |simd64-summary|  Summary", doc.lines[7])
        end)
        it("tags each heading and declares nothing else", function()
            local _, line = find(doc.lines, "%*simd64%-summary%*$")
            assert.are.equal("SUMMARY", line:match("^(.-)%s+%*"))
            for _, t in ipairs(doc.tags) do
                assert.is_truthy(doc.lines[t.line]:find("*" .. t.name .. "*", 1, true), t.name)
            end
            assert.are.equal(#doc.tags, #help.tags_in(doc.lines))
            assert.is_true(#doc.tags > 2)
        end)
    end)

    it("links the proposals the text names and the one it extends", function()
        local doc = help_simd.render("268", fixtures.read(fixtures.simd_related))
        assert.are.equal(
            "Extends: |simd219|",
            find(doc.lines, "^Extends: ") and select(2, find(doc.lines, "^Extends: "))
        )
        assert.is_truthy(find(doc.lines, "|simd219|"))
    end)

    it("links a markdown link and a bare mention", function()
        local doc = help_simd.render("1", {
            "---",
            "simd: '0001'",
            "title: T",
            "authors: A",
            "---",
            "## Summary",
            "See [SIMD-0033](./0033-timely-vote-credits.md) and SIMD-0064, as in [x](./0161-agave-v2.md#summary).",
        })
        assert.is_truthy(find(doc.lines, "^See |simd33| and |simd64|, as in |simd161%-summary|%.$"))
        assert.are.equal("Authors: A", doc.lines[3])
    end)

    it("renders an empty text as the header and the footer", function()
        local doc = help_simd.render("5", {})
        assert.are.equal("*simd5.txt*  SIMD 5", doc.lines[1]:match("^(.-)%s+%*simd5%*$"))
        assert.are.equal("SIMD-0005", doc.lines[2])
        assert.are.equal(6, #doc.lines)
        assert.are.equal(2, #doc.tags)
    end)
end)
