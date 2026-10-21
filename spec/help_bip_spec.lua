local help_bip = require("rfc.help_bip")
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
    describe("of BIP 32", function()
        local doc
        before_each(function()
            doc = help_bip.render("32", fixtures.read(fixtures.bip32))
        end)
        it("opens with the file tag line and the header from the preamble", function()
            assert.are.equal(
                "*bip32.txt*  Hierarchical Deterministic Wallets",
                doc.lines[1]:match("^(.-)%s+%*bip32%*$")
            )
            assert.are.equal(78, #doc.lines[1])
            assert.are.equal(
                "BIP-32  Layer: Applications  Status: Deployed  Type: Informational  Assigned: 2012-02-11",
                doc.lines[2]
            )
            assert.are.equal("Authors: Pieter Wuille <pieter.wuille@gmail.com>", doc.lines[3])
            assert.are.equal("", doc.lines[4])
            assert.are.equal(help.MODELINE, doc.lines[#doc.lines - 1])
            assert.are.equal(help.FOOTER, doc.lines[#doc.lines])
        end)
        it("lists the headings as a table of contents of links, indented by level", function()
            assert.are.equal("CONTENTS", doc.lines[5])
            assert.are.equal("  |bip32-abstract|  Abstract", doc.lines[6])
            assert.are.equal("    |bip32-conventions|  Conventions", doc.lines[10])
            assert.is_truthy(
                find(doc.lines, "^      |bip32%-per%-office%-balances%-m%-ih|  Per%-office balances: m/iH$")
            )
        end)
        it("keeps the text above the preamble and leaves the preamble out", function()
            assert.is_truthy(find(doc.lines, "^RECENT CHANGES:$"))
            assert.is_nil(find(doc.lines, "^  BIP: 32$"))
            assert.is_nil(find(doc.lines, "^<pre>$"))
        end)
        it("tags each heading, the top two levels in capitals, the rest as written", function()
            local _, line = find(doc.lines, "%*bip32%-abstract%*$")
            assert.are.equal("ABSTRACT", line:match("^(.-)%s+%*"))
            assert.are.equal(78, #line)
            local _, sub = find(doc.lines, "%*bip32%-per%-office%-balances%-m%-ih%*$")
            assert.are.equal("Per-office balances: m/iH", sub:match("^(.-)%s+%*"))
        end)
        it("declares the file, every heading and nothing else as tags", function()
            for _, t in ipairs(doc.tags) do
                assert.is_truthy(doc.lines[t.line]:find("*" .. t.name .. "*", 1, true), t.name)
            end
            assert.are.equal(2 + 33, #doc.tags)
            assert.are.equal(#doc.tags, #help.tags_in(doc.lines))
        end)
    end)

    it("links the proposals the text names and its requirement", function()
        local doc = help_bip.render("341", fixtures.read(fixtures.bip341))
        assert.are.equal("Requires: |bip340|", doc.lines[3])
        local _, line = find(doc.lines, "Schnorr signatures %(|bip340|%)")
        assert.is_truthy(line)
        assert.is_nil(line:find("[[", 1, true))
        assert.is_truthy(line:find("|bip114|, |bip117|", 1, true))
    end)

    it("numbers the footnotes in the text and lists them where the references stand", function()
        local doc = help_bip.render("341", fixtures.read(fixtures.bip341))
        assert.is_truthy(find(doc.lines, "new security assumptions %[1%]%. Specifically"))
        local i, line = find(doc.lines, "^%[1%] What does not adding security assumptions mean%? ")
        assert.is_truthy(i)
        assert.is_nil(line:find("'''", 1, true))
        assert.is_truthy(doc.lines[i + 1]:match("^%[2%] "))
        assert.is_nil(find(doc.lines, "<references"))
    end)

    it("lays a wikitable out as columns and links a section of another proposal", function()
        local doc = help_bip.render("22", fixtures.read(fixtures.bip22))
        local i = find(doc.lines, "^  Key%s+Required%s+Type%s+Description$")
        assert.is_truthy(i)
        assert.are.equal("  template request", doc.lines[i - 1])
        assert.is_truthy(doc.lines[i + 1]:match("^  %-+%s+%-+%s+%-+%s+%-+$"))
        assert.is_truthy(
            doc.lines[i + 2]:match('^  capabilities%s+No%s+Array of Strings%s+SHOULD contain .- "longpoll"')
        )
        assert.is_truthy(find(doc.lines, "or a |bip23%-block%-proposal|%.$"))
    end)

    it("links a section of the document itself by its own tag", function()
        local doc =
            help_bip.render("22", { "<pre>", "  BIP: 22", "  Title: T", "</pre>", "==A==", "see [[#a-b|x]] here" })
        assert.is_truthy(find(doc.lines, "^see |bip22%-a%-b| here$"))
    end)

    it("renders a proposal written in markdown", function()
        local doc = help_bip.render("3", fixtures.read(fixtures.bip3))
        assert.are.equal("*bip3.txt*  Updated BIP Process", doc.lines[1]:match("^(.-)%s+%*bip3%*$"))
        assert.are.equal("BIP-3  Status: Deployed  Type: Process  Assigned: 2025-01-09", doc.lines[2])
        assert.are.equal("Requires: |bip123|", doc.lines[3])
        assert.are.equal("Replaces: |bip2|", doc.lines[4])
        assert.is_truthy(doc.lines[5]:match("^Authors: Murch"))
        assert.are.equal("CONTENTS", doc.lines[7])
        assert.are.equal("  |bip3-abstract|  Abstract", doc.lines[8])
        assert.is_truthy(find(doc.lines, "It replaces |bip2| with a streamlined process"))
        assert.is_nil(find(doc.lines, "^  BIP: 3$"))
    end)

    it("renders an empty text as the header and the footer", function()
        local doc = help_bip.render("1", {})
        assert.are.equal("*bip1.txt*  BIP 1", doc.lines[1]:match("^(.-)%s+%*bip1%*$"))
        assert.are.equal("BIP-1", doc.lines[2])
        assert.are.equal(6, #doc.lines)
        assert.are.equal(2, #doc.tags)
    end)
end)
