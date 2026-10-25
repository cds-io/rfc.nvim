local eip = require("rfc.source.eip")
local fixtures = require("spec.fixtures")

describe("frontmatter", function()
    it("reads the fields and where the body starts", function()
        local fields, body = eip.frontmatter(fixtures.read(fixtures.eip1559))
        assert.are.equal("1559", fields.eip)
        assert.are.equal("Fee market change for ETH 1.0 chain", fields.title)
        assert.are.equal("Final", fields.status)
        assert.are.equal("Standards Track", fields.type)
        assert.are.equal("Core", fields.category)
        assert.are.equal("2019-04-13", fields.created)
        assert.are.equal("2718, 2930", fields.requires)
        assert.are.equal(12, body)
    end)
    it("reads a moved stub", function()
        local fields = eip.frontmatter(fixtures.read(fixtures.eip20_moved))
        assert.are.equal("Moved", fields.status)
        assert.are.equal("ERC", fields.category)
    end)
    it("joins a value continued on indented lines", function()
        local fields = eip.frontmatter({ "---", "author: A", "  B", "title: T", "---", "body" })
        assert.are.equal("A B", fields.author)
        assert.are.equal("T", fields.title)
    end)
    it("is empty without a frontmatter", function()
        local fields, body = eip.frontmatter({ "## Heading", "text" })
        assert.are.same({}, fields)
        assert.are.equal(1, body)
    end)
end)

describe("fences", function()
    it("finds a fenced block with its language", function()
        assert.are.same({ { first = 53, last = 302, lang = "python" } }, eip.fences(fixtures.read(fixtures.eip1559)))
    end)
    it("reads a language after a space and a fence without one", function()
        local fences = eip.fences(fixtures.read(fixtures.erc20))
        assert.are.same({ first = 45, last = 47, lang = "js" }, fences[1])
        assert.are.same({ first = 42, last = 44, lang = "" }, eip.fences(fixtures.read(fixtures.eip1))[1])
    end)
    it("runs an unterminated fence to the end", function()
        assert.are.same({ { first = 2, last = 3, lang = "" } }, eip.fences({ "a", "```", "b" }))
    end)
end)

describe("headings", function()
    it("reads every heading with its level, outside fenced code", function()
        local headings = eip.headings(fixtures.read(fixtures.eip1559))
        assert.are.equal(13, #headings)
        assert.are.same({ level = 2, title = "Simple Summary", line = 13 }, headings[1])
        assert.are.same({ level = 3, title = "Block Hash Changing", line = 307 }, headings[6])
    end)
    it("reads four levels", function()
        local headings = eip.headings(fixtures.read(fixtures.erc20))
        assert.are.same({ level = 4, title = "name", line = 37 }, headings[7])
    end)
    it("ignores a # inside a fence", function()
        assert.are.same({ { level = 2, title = "A", line = 1 } }, eip.headings({ "## A", "```py", "# comment", "```" }))
    end)
end)

describe("requires", function()
    it("lists the numbers of the requires field", function()
        assert.are.same({ "2718", "2930" }, eip.requires({ requires = "2718, 2930" }))
        assert.are.same({}, eip.requires({}))
    end)
end)

describe("mentions", function()
    it("finds a link whose text names an EIP, the span being the whole link", function()
        local line = fixtures.read(fixtures.eip1559)[17]
        assert.are.same({ { kind = "eip", first = 20, last = 44, id = "2718" } }, eip.mentions(line))
    end)
    it("reads the kind from the link text", function()
        local found = eip.mentions("token standards ([ERC-20](./eip-20.md)), name registries ([ERC-137](./eip-137.md))")
        assert.are.equal(2, #found)
        assert.are.same({ kind = "erc", first = 18, last = 38, id = "20" }, found[1])
        assert.are.equal("137", found[2].id)
    end)
    it("finds bare mentions", function()
        assert.are.same({
            { kind = "eip", first = 5, last = 11, id = "155" },
            { kind = "erc", first = 17, last = 22, id = "20" },
        }, eip.mentions("see EIP-155 and ERC-20 here"))
    end)
    it("finds nothing in plain text or a word that only contains one", function()
        assert.are.same({}, eip.mentions("the base fee per gas is burned"))
        assert.are.same({}, eip.mentions("see pre-EIP-155 signing"))
    end)
end)

describe("mentions after a link", function()
    it("keep their position", function()
        local line = "see [EIP-2718](./eip-2718.md) and ERC-20."
        local found = eip.mentions(line)
        assert.are.equal("ERC-20", line:sub(found[2].first, found[2].last))
    end)
end)

describe("plain", function()
    it("drops tags, turns a code tag into backticks and unescapes entities", function()
        assert.are.equal(
            "`0x` prefixed hex &amp; more.",
            eip.plain("<td><p><code>0x</code> prefixed hex &amp;amp; more.</p></td>")
        )
        assert.are.equal("Definitions", eip.plain('<a href="#definitions">Definitions</a>'))
    end)
    it("turns emphasis into its text and keeps code spans and autolinks", function()
        assert.are.equal("bold and em, `*/*` as is", eip.plain("**bold** and *em*, `*/*` as is"))
        assert.are.equal("see <https://example.org/a> now", eip.plain("see <https://example.org/a> now"))
        assert.are.equal("2 * 3 * 4", eip.plain("2 * 3 * 4"))
    end)
end)

describe("tables", function()
    it("reads an HTML table's rows as plain cells", function()
        local tables = eip.tables(fixtures.read(fixtures.erc1123))
        assert.are.equal(44, #tables)
        assert.are.same({
            first = 124,
            last = 139,
            header = false,
            rows = { { "Prefixed", "`0xdeadbeef`" }, { "Unprefixed", "`deadbeef`" } },
        }, tables[1])
    end)
    it("reads a markdown table with its heading row", function()
        local tables =
            eip.tables({ "text", "| Constant | Value |", "| - | - |", "| `A` | `1` |", "| `B` | `2` |", "", "more" })
        local rows = { { "Constant", "Value" }, { "`A`", "`1`" }, { "`B`", "`2`" } }
        assert.are.same({ { first = 2, last = 5, header = true, rows = rows } }, tables)
    end)
    it("marks an HTML heading row", function()
        local tables =
            eip.tables({ "<table>", "<tr><th>A</th><th>B</th></tr>", "<tr><td>1</td><td>2</td></tr>", "</table>" })
        assert.is_true(tables[1].header)
        assert.are.same({ { "A", "B" }, { "1", "2" } }, tables[1].rows)
    end)
    it("finds none in plain text", function()
        assert.are.same({}, eip.tables({ "a | b", "no table here" }))
    end)
end)

describe("blocks", function()
    it("reads the body as headings, fences, tables and lines, every text plain", function()
        local blocks = eip.blocks({
            "## The *Compiler* Object",
            "Some **bold** text.",
            "",
            "```js",
            "x = *not emphasis*",
            "```",
            "| A | B |",
            "| - | - |",
            "| <code>1</code> | 2 |",
        })
        assert.are.same({
            { kind = "heading", line = 1, level = 2, title = "The Compiler Object" },
            { kind = "line", line = 2, text = "Some bold text." },
            { kind = "line", line = 3, text = "" },
            { kind = "fence", line = 4, lang = "js", code = { "x = *not emphasis*" } },
            { kind = "table", line = 7, header = true, rows = { { "A", "B" }, { "`1`", "2" } } },
        }, blocks)
    end)
    it("starts at the given line and runs an open fence to the end", function()
        local blocks = eip.blocks({ "---", "x: 1", "---", "## A", "```", "code" }, 4)
        assert.are.same({
            { kind = "heading", line = 4, level = 2, title = "A" },
            { kind = "fence", line = 5, lang = "", code = { "code" } },
        }, blocks)
    end)
end)

describe("ordered lists in blocks", function()
    local function texts(blocks)
        local out = {}
        for _, b in ipairs(blocks) do
            table.insert(out, b.text or b.kind)
        end
        return out
    end
    it("numbers a run of items written as 1. in sequence, a blank line between items allowed", function()
        assert.are.same(
            { "1. a", "2. b", "", "3. c", "text", "1. d", "2. e" },
            texts(eip.blocks({ "1. a", "1. b", "", "1. c", "text", "1. d", "1. e" }))
        )
    end)
    it("numbers a nested list on its own, by indent", function()
        assert.are.same(
            { "1. a", "   1. x", "   2. y", "2. b", "   1. z" },
            texts(eip.blocks({ "1. a", "   1. x", "   1. y", "1. b", "   1. z" }))
        )
    end)
    it("starts where the author starts and keeps a sequence the author wrote", function()
        assert.are.same({ "3. a", "4. b" }, texts(eip.blocks({ "3. a", "3. b" })))
        assert.are.same({ "1. a", "2. b", "3. c" }, texts(eip.blocks({ "1. a", "2. b", "3. c" })))
    end)
    it("leaves a numbered line inside a fence alone, and a fence ends the list", function()
        local blocks = eip.blocks({ "1. a", "```", "1. x", "1. y", "```", "1. b" })
        assert.are.same({ "1. x", "1. y" }, blocks[2].code)
        assert.are.same({ "1. a", "fence", "1. b" }, texts(blocks))
    end)
    it("is not fooled by a number that is not an item", function()
        assert.are.same({ "1.5 is a ratio", "1.b" }, texts(eip.blocks({ "1.5 is a ratio", "1.b" })))
    end)
end)

describe("listing", function()
    it("reads each row's number and title under its status", function()
        local entries = eip.listing(fixtures.read(fixtures.eips_all))
        assert.are.equal(5, #entries)
        assert.are.same(
            { id = "1", title = "EIP Purpose and Guidelines", status = "Living", category = "All" },
            entries[1]
        )
        assert.are.same(
            { id = "1559", title = "Fee market change for ETH 1.0 chain", status = "Final", category = "All" },
            entries[5]
        )
    end)
    it("reads the ERC listing", function()
        local entries = eip.listing(fixtures.read(fixtures.ercs_all))
        assert.are.equal(3, #entries)
        assert.are.same({ id = "20", title = "Token Standard", status = "Final", category = "All" }, entries[2])
    end)
    it("takes the category from the page's title", function()
        local entries = eip.listing({
            '<h1 class="post-title">Core</h1>',
            '<h2 id="final">Final</h2>',
            '<td class="eipnum"><a href="/EIPS/eip-1559">1559</a></td>',
            '<td class="title">Fee market change for ETH 1.0 chain</td>',
        })
        assert.are.same(
            { { id = "1559", title = "Fee market change for ETH 1.0 chain", status = "Final", category = "Core" } },
            entries
        )
    end)
    it("is empty for a page with no rows", function()
        assert.are.same({}, eip.listing({ "<html>", '<h2 id="final">Final</h2>', "</html>" }))
    end)
end)
