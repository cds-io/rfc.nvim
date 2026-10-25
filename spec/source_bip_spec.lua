local bip = require("rfc.source.bip")
local fixtures = require("spec.fixtures")

describe("format", function()
    it("tells mediawiki by its == headings and markdown otherwise", function()
        assert.are.equal("mediawiki", bip.format(fixtures.read(fixtures.bip32)))
        assert.are.equal("markdown", bip.format(fixtures.read(fixtures.bip3)))
        assert.are.equal("markdown", bip.format({}))
    end)
end)

describe("preamble", function()
    it("reads the fields of the <pre> block and where it sits", function()
        local fields, first, last = bip.preamble(fixtures.read(fixtures.bip32))
        assert.are.equal("32", fields.bip)
        assert.are.equal("Hierarchical Deterministic Wallets", fields.title)
        assert.are.equal("Pieter Wuille <pieter.wuille@gmail.com>", fields.authors)
        assert.are.equal("Deployed", fields.status)
        assert.are.equal("Informational", fields.type)
        assert.are.equal("Applications", fields.layer)
        assert.are.equal("2012-02-11", fields.assigned)
        assert.are.equal("BSD-2-Clause", fields.license)
        assert.are.equal(9, first)
        assert.are.equal(18, last)
    end)
    it("reads a markdown proposal's fenced block, joining a continued value", function()
        local fields, first, last = bip.preamble(fixtures.read(fixtures.bip3))
        assert.are.equal("3", fields.bip)
        assert.are.equal("123", fields.requires)
        assert.are.equal("2", fields.replaces)
        local gnusha =
            "https://gnusha.org/pi/bitcoindev/59fa94cea6f70e02b1ce0da07ae230670730171c.camel@timruffing.de/#t"
        assert.are.equal(
            "2024-05-13: https://github.com/murchandamus/bips/pull/2 2024-04-02: " .. gnusha,
            fields.discussion
        )
        assert.are.equal(1, first)
        assert.are.equal(14, last)
    end)
    it("passes a code block that is no preamble", function()
        local fields, first, last =
            bip.preamble({ "<pre>", "x = 1", "</pre>", "<pre>", "  BIP: 5", "  Title: T", "</pre>" })
        assert.are.same({ bip = "5", title = "T" }, fields)
        assert.are.equal(4, first)
        assert.are.equal(7, last)
    end)
    it("is empty without one", function()
        local fields, first, last = bip.preamble({ "==Abstract==", "text" })
        assert.are.same({}, fields)
        assert.is_nil(first)
        assert.is_nil(last)
    end)
end)

describe("headings", function()
    it("reads every == heading with its level and plain title", function()
        local headings = bip.headings(fixtures.read(fixtures.bip32))
        assert.are.equal(33, #headings)
        assert.are.same({ level = 1, title = "Abstract", line = 20 }, headings[1])
        assert.are.same({ level = 2, title = "Conventions", line = 42 }, fixtures.find(headings, "line", 42))
        assert.are.same(
            { level = 3, title = "Private parent key → private child key", line = 72 },
            fixtures.find(headings, "line", 72)
        )
        assert.are.same(
            { level = 3, title = "Per-office balances: m/iH", line = 178 },
            fixtures.find(headings, "line", 178)
        )
    end)
    it("allows spaces inside the signs and ignores a heading inside code", function()
        local headings = bip.headings({ "== Spaced ==", "<pre>", "==not one==", "</pre>", "=====Deep=====" })
        assert.are.same(
            { { level = 1, title = "Spaced", line = 1 }, { level = 4, title = "Deep", line = 5 } },
            headings
        )
    end)
end)

describe("code", function()
    it("reads <pre> and <source> blocks with their language and lines", function()
        local blocks = bip.code({ "<pre>", "a", "</pre>", "", '<source lang="python">', "x = 1", "</source>" })
        assert.are.same({
            { first = 1, last = 3, lang = "", code = { "a" } },
            { first = 5, last = 7, lang = "python", code = { "x = 1" } },
        }, blocks)
    end)
    it("keeps text sharing a line with the tags", function()
        assert.are.same(
            { { first = 1, last = 3, lang = "", code = { "first", "b", "last" } } },
            bip.code({ "<pre>first", "b", "last</pre>" })
        )
    end)
    it("reads a block that opens and closes on one line, and passes one inside other text", function()
        assert.are.same({ { first = 1, last = 1, lang = "", code = { "a" } } }, bip.code({ "<pre>a</pre>" }))
        assert.are.same({}, bip.code({ "## step: <pre>a</pre>" }))
    end)
    it("runs an unterminated block to the end", function()
        assert.are.same(
            { { first = 2, last = 4, lang = "", code = { "a", "b" } } },
            bip.code({ "t", "<pre>", "a", "b" })
        )
    end)
end)

describe("tables", function()
    it("reads a wikitable's caption, header and rows as plain cells", function()
        local tables = bip.tables(fixtures.read(fixtures.bip22))
        assert.are.equal(30, tables[1].first)
        assert.are.equal(38, tables[1].last)
        assert.is_true(tables[1].header)
        assert.are.equal("template request", tables[1].caption)
        assert.are.same({ "Key", "Required", "Type", "Description" }, tables[1].rows[1])
        assert.are.same({
            "capabilities",
            "No",
            "Array of Strings",
            'SHOULD contain a list of the following, to indicate client-side support: "longpoll", "coinbasetxn", '
                .. '"coinbasevalue", "proposal", "serverlist", "workid", and any of the mutations',
        }, tables[1].rows[2])
        assert.are.same({ "mode", "No", "String", 'MUST be "template" or omitted' }, tables[1].rows[3])
    end)
    it("reads one cell per line and a table without a header", function()
        local tables = bip.tables({ "{|", "| a", "| b", "|-", "| c", "| d", "|}" })
        assert.are.same({ { first = 1, last = 7, header = false, rows = { { "a", "b" }, { "c", "d" } } } }, tables)
    end)
    it("reads a |+ caption", function()
        local tables = bip.tables({ "{|", "|+ Caption", "! a !! b", "|}" })
        assert.are.same(
            { { first = 1, last = 4, caption = "Caption", header = true, rows = { { "a", "b" } } } },
            tables
        )
    end)
    it("finds none in text", function()
        assert.are.same({}, bip.tables({ "| not a table", "text" }))
    end)
end)

describe("footnotes", function()
    it("numbers each ref in order, leaves a marker and collects the note", function()
        local lines, notes = bip.footnotes(fixtures.read(fixtures.bip341))
        assert.are.equal(23, #notes)
        assert.is_truthy(lines[31]:find("new security assumptions [1].", 1, true))
        assert.is_truthy(notes[1].text:match("^What does not adding security assumptions mean%? Unforgeability"))
        assert.are.equal(1, notes[1].n)
        assert.are.equal("<references />", lines[308])
    end)
    it("gives a named ref one number for every use", function()
        local lines, notes = bip.footnotes({ 'a<ref name="x">X</ref> b<ref name="x" /> c<ref>Y</ref>' })
        assert.are.same({ "a [1] b [1] c [2]" }, lines)
        assert.are.same({ { n = 1, text = "X" }, { n = 2, text = "Y" } }, notes)
    end)
    it("closes a ref on a later line, keeping the line count", function()
        local lines, notes = bip.footnotes({ "a<ref>first", "second</ref> b", "c" })
        assert.are.same({ "a [1]", " b", "c" }, lines)
        assert.are.same({ { n = 1, text = "first second" } }, notes)
    end)
end)

describe("mentions", function()
    it("reads a link to a proposal, with a section when it names one", function()
        local line = 'see [[bip-0340.mediawiki|BIP340]] and [[bip-0023.mediawiki#block-proposal|"proposal"]]'
        assert.are.same({
            { kind = "bip", id = "340", first = 5, last = 33 },
            { kind = "bip", id = "23", section = "block-proposal", first = 39, last = 86 },
        }, bip.mentions(line))
    end)
    it("reads a link into the document itself", function()
        assert.are.same(
            { { kind = "bip", section = "optional-long-polling", first = 1, last = 37 } },
            bip.mentions('[[#optional-long-polling|"longpoll"]] x')
        )
    end)
    it("reads a markdown link", function()
        assert.are.same(
            { { kind = "bip", id = "2", first = 13, last = 39 } },
            bip.mentions("It replaces [BIP 2](bip-0002.mediawiki) with")
        )
    end)
    it("reads bare mentions in every spelling, without leading zeros", function()
        local found = bip.mentions("see BIP 32, BIP-0032, BIP32 and BIP0032; BIPS and BIP32x are none")
        assert.are.equal(4, #found)
        for _, m in ipairs(found) do
            assert.are.equal("32", m.id)
        end
        assert.are.same({ first = 5, last = 10 }, { first = found[1].first, last = found[1].last })
    end)
    it("keeps the position of a bare mention after a link", function()
        local line = "see [[bip-0340.mediawiki|BIP340]] and BIP 32."
        local found = bip.mentions(line)
        assert.are.equal("BIP 32", line:sub(found[2].first, found[2].last))
    end)
    it("finds a link's text once", function()
        local found = bip.mentions(fixtures.read(fixtures.bip341)[35])
        local ids = {}
        for _, m in ipairs(found) do
            table.insert(ids, m.id)
        end
        assert.are.same({ "340", "114", "117", "118" }, ids)
    end)
end)

describe("plain", function()
    it("drops bold and italic marks", function()
        assert.are.equal("bold and em", bip.plain("'''bold''' and ''em''"))
    end)
    it("writes code spans in backticks", function()
        assert.are.equal("`x` `y` z: `w`", bip.plain("<code>x</code> <tt>y</tt> z: <pre>w</pre>"))
    end)
    it("drops tags and keeps their text", function()
        assert.are.equal("IL 231 ab", bip.plain("I<sub>L</sub> 2<sup>31</sup> a<br/>b"))
        assert.are.equal("Optional parameters", bip.plain('<span id="optional-params"></span>Optional parameters'))
    end)
    it("writes an external link as its text and address", function()
        assert.are.equal("SEC1 (https://x.org/a)", bip.plain("[https://x.org/a SEC1]"))
        assert.are.equal("https://x.org", bip.plain("[https://x.org]"))
    end)
    it("keeps a link to a proposal and unwraps any other wiki link", function()
        assert.are.equal("[[bip-0032.mediawiki|BIP 32]] [[#a|b]]", bip.plain("[[bip-0032.mediawiki|BIP 32]] [[#a|b]]"))
        assert.are.equal("code and site", bip.plain("[[bip-0032/reference.py|code]] and [[https://x.org|site]]"))
        assert.are.equal("", bip.plain("[[File:x.png|300px]]"))
    end)
    it("unescapes entities", function()
        assert.are.equal("→ & < ≤ é", bip.plain("&rarr; &amp; &lt; &le; &#233;"))
    end)
end)

describe("blocks", function()
    it("classifies every line, the text already plain", function()
        local blocks = bip.blocks({
            "==T==",
            "a '''b'''<ref>note</ref>",
            "<pre>",
            "c",
            "</pre>",
            "{|",
            "! a !! b",
            "|-",
            "| 1 || 2",
            "|}",
            "<references />",
        })
        assert.are.same({
            { kind = "heading", line = 1, level = 1, title = "T" },
            { kind = "line", line = 2, text = "a b [1]" },
            { kind = "fence", line = 3, lang = "", code = { "c" } },
            { kind = "table", line = 6, header = true, rows = { { "a", "b" }, { "1", "2" } } },
            { kind = "notes", line = 11, notes = { { n = 1, text = "note" } } },
        }, blocks)
    end)
    it("leaves out the lines asked", function()
        local blocks = bip.blocks({ "x", "<pre>", "  BIP: 1", "</pre>", "y" }, { first = 2, last = 4 })
        assert.are.same({ { kind = "line", line = 1, text = "x" }, { kind = "line", line = 5, text = "y" } }, blocks)
    end)
end)

describe("index", function()
    it("reads every row of the repository's README table", function()
        local entries = bip.index(fixtures.read(fixtures.bips_readme))
        assert.are.equal(213, #entries)
        assert.are.same(
            { id = "1", title = "BIP Purpose and Guidelines", status = "Closed", type = "Process", layer = "" },
            entries[1]
        )
        local three = fixtures.find(entries, "id", "3")
        assert.are.equal("Updated BIP Process", three.title)
        assert.are.equal("Deployed", three.status)
        assert.are.equal("Applications", fixtures.find(entries, "id", "32").layer)
    end)
    it("reads nothing from a page without the table", function()
        assert.are.same({}, bip.index({ "text" }))
    end)
end)
