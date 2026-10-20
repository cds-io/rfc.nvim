local help_eip = require("rfc.help_eip")
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
    describe("of EIP-1559", function()
        local doc, lines
        before_each(function()
            lines = fixtures.read(fixtures.eip1559)
            doc = help_eip.render("eip", "1559", lines)
        end)
        it("opens with the file tag line and the header from the frontmatter", function()
            assert.are.equal(
                "*eip1559.txt*  Fee market change for ETH 1.0 chain",
                doc.lines[1]:match("^(.-)%s+%*eip1559%*$")
            )
            assert.are.equal(
                "EIP-1559  Status: Final  Type: Standards Track  Category: Core  Created: 2019-04-13",
                doc.lines[2]
            )
            assert.are.equal("Requires: |eip2718|, |eip2930|", doc.lines[3])
            assert.is_truthy(doc.lines[4]:match("^Author: Vitalik Buterin"))
            assert.are.equal("", doc.lines[5])
            assert.are.equal(help.MODELINE, doc.lines[#doc.lines])
        end)
        it("lists the headings as a table of contents of links, indented by level", function()
            assert.are.equal("CONTENTS", doc.lines[6])
            assert.are.equal("  |eip1559-simple-summary|  Simple Summary", doc.lines[7])
            assert.are.equal("    |eip1559-block-hash-changing|  Block Hash Changing", doc.lines[12])
            assert.are.equal("", doc.lines[20])
        end)
        it("tags each heading, level-two headings in capitals", function()
            local i, line = find(doc.lines, "%*eip1559%-specification%*$")
            assert.are.equal("SPECIFICATION", line:match("^(.-)%s+%*"))
            assert.are.equal(78, #line)
            assert.is_truthy(i)
            local _, sub = find(doc.lines, "%*eip1559%-gasprice%*$")
            assert.are.equal("GASPRICE", sub:match("^(.-)%s+%*"))
        end)
        it("turns a fenced block into a help code block, indented", function()
            local open = find(doc.lines, "^>python$")
            assert.is_truthy(open)
            assert.is_truthy(doc.lines[open + 1]:match("^    "))
            local close = find(doc.lines, "^<$")
            assert.is_true(close > open)
            assert.are.equal(lines[302 - 1], doc.lines[close - 1]:sub(5))
        end)
        it("links the proposals the text names", function()
            local _, line = find(doc.lines, "^We introduce a new ")
            assert.is_truthy(line:match("^We introduce a new |eip2718| transaction type"))
        end)
        it("declares the file, every heading and nothing else as tags", function()
            local names = {}
            for _, t in ipairs(doc.tags) do
                names[t.name] = t.line
                assert.is_truthy(doc.lines[t.line]:find("*" .. t.name .. "*", 1, true), t.name)
            end
            assert.are.equal(1, names["eip1559"])
            assert.are.equal(1, names["eip1559.txt"])
            assert.is_truthy(names["eip1559-security-considerations"])
            assert.are.equal(2 + 13, #doc.tags)
            assert.are.equal(#doc.tags, #help.tags_in(doc.lines))
        end)
    end)

    it("gives an ERC its EIP number as a second tag", function()
        local doc = help_eip.render("erc", "20", fixtures.read(fixtures.erc20))
        assert.is_truthy(doc.lines[1]:match("^%*erc20%.txt%*  Token Standard%s+%*erc20%* %*eip20%*$"))
        assert.are.equal("eip20", doc.tags[3].name)
        assert.are.equal(
            "ERC-20  Status: Final  Type: Standards Track  Category: ERC  Created: 2015-11-19",
            doc.lines[2]
        )
    end)
    it("numbers a repeated heading", function()
        local doc = help_eip.render("eip", "1", { "## A", "x", "## A", "y" })
        assert.are.equal("eip1-a", doc.tags[3].name)
        assert.are.equal("eip1-a-2", doc.tags[4].name)
    end)
    it("renders a moved stub with a link to where it went", function()
        local doc = help_eip.render("eip", "20", fixtures.read(fixtures.eip20_moved))
        assert.is_truthy(doc.lines[1]:match("^%*eip20%.txt%*  EIP 20"))
        assert.are.equal("EIP-20  Status: Moved  Category: ERC", doc.lines[2])
        assert.are.equal("Moved: see |erc20|", doc.lines[3])
    end)
    it("closes a fence the text leaves open", function()
        local doc = help_eip.render("eip", "1", { "## A", "```", "code" })
        assert.are.same(
            { ">", "    code", "<" },
            { doc.lines[#doc.lines - 4], doc.lines[#doc.lines - 3], doc.lines[#doc.lines - 2] }
        )
    end)
    it("renders empty text", function()
        local doc = help_eip.render("eip", "1", {})
        assert.are.equal(5, #doc.lines)
        assert.are.equal(2, #doc.tags)
    end)
end)
