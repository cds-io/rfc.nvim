local subjects = require("rfc.subjects")
local source = require("rfc.source.subjects")
local help = require("rfc.help")
local outline = require("rfc.outline")
local fixtures = require("spec.fixtures")

local DOC = {
    prefix = "rfc",
    title = "RFCs by subject",
    about = "From rfc-editor.github.io/rfc-subject-tags, the RFC Editor's subject tags (beta).",
}

--- lines[first..last]; the plain tier has no vim.list_slice.
local function slice(lines, first, last)
    local out = {}
    for i = first, last do
        table.insert(out, lines[i])
    end
    return out
end

describe("tag", function()
    it("slugs each level and joins them", function()
        assert.are.equal("rfc-subjects-web-http", subjects.tag("rfc", { "web", "HTTP" }))
        assert.are.equal(
            "bip-subjects-layer-consensus-soft-fork",
            subjects.tag("bip", { "Layer", "Consensus (soft fork)" })
        )
        assert.are.equal("rfc-subjects-security-pki-x.509", subjects.tag("rfc", { "security", "PKI", "X.509" }))
    end)
end)

describe("render", function()
    local doc
    before_each(function()
        doc = subjects.render(DOC, source.tree(source.rfc(fixtures.read(fixtures.rfc_tags))))
    end)
    it("writes the title line, the about line, the contents block, one section per node, then the footer", function()
        assert.are.same({
            help.with_tag("*rfc-subjects.txt*  RFCs by subject", "rfc-subjects"),
            DOC.about,
            "",
            "|rfc-subjects-arpanet|  ARPANET (3)",
            "|rfc-subjects-data-formats|  data formats (1)",
            "  |rfc-subjects-data-formats-internationalization|  internationalization (1)",
            "    |rfc-subjects-data-formats-internationalization-character-sets|  character sets (1)",
            "      |rfc-subjects-data-formats-internationalization-character-sets-ascii|  ASCII (1)",
            "|rfc-subjects-internet-layer|  internet layer (1)",
            "  |rfc-subjects-internet-layer-ipv4|  IPv4 (1)",
            "|rfc-subjects-messaging|  messaging (1)",
            "  |rfc-subjects-messaging-email|  email (1)",
            "    |rfc-subjects-messaging-email-mailing-lists|  mailing lists (1)",
            "|rfc-subjects-web|  web (4)",
            "  |rfc-subjects-web-http|  HTTP (3)",
            "  |rfc-subjects-web-uri|  URI (1)",
            "",
            help.with_tag("ARPANET  (3)", "rfc-subjects-arpanet"),
            "|rfc37|  Network Meeting Epilogue, etc (1970)",
            "|rfc155|  ARPA Network mailing lists (1971)",
            '|rfc175|  Comments on "Socket Conventions Reconsidered" (1971)',
            "",
            help.with_tag("data formats  (1)", "rfc-subjects-data-formats"),
            "",
        }, slice(doc.lines, 1, 24))
        assert.are.equal(help.FOOTER, doc.lines[#doc.lines])
        assert.are.equal(help.MODELINE, doc.lines[#doc.lines - 1])
        assert.are.equal("", doc.lines[#doc.lines - 2])
    end)
    it("declares the file tags and one tag per node, each on its heading line", function()
        assert.are.same({ name = "rfc-subjects", line = 1 }, doc.tags[1])
        assert.are.same({ name = "rfc-subjects.txt", line = 1 }, doc.tags[2])
        assert.are.equal(2 + 13, #doc.tags)
        assert.are.same({ name = "rfc-subjects-arpanet", line = 18 }, doc.tags[3])
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
    it("gives the outline one heading per node at the node's depth", function()
        local headings = outline.of(doc.lines)
        assert.are.equal(13, #headings)
        assert.are.same({ tag = "rfc-subjects-arpanet", text = "ARPANET  (3)", level = 1, line = 18 }, headings[1])
        assert.are.equal(4, headings[5].level)
        assert.are.equal("ASCII  (1)", headings[5].text)
    end)
    it("numbers a repeated tag so the tags file never holds two", function()
        local forest = source.tree({
            source.entry("1", "A (2000)", { { "naming", "WHOIS" } }),
            source.entry("2", "B (2001)", { { "naming", "WHOIS++" } }),
        })
        local d = subjects.render(DOC, forest)
        local names = {}
        for _, t in ipairs(d.tags) do
            names[t.name] = (names[t.name] or 0) + 1
        end
        assert.are.equal(1, names["rfc-subjects-naming-whois"])
        assert.are.equal(1, names["rfc-subjects-naming-whois-2"])
    end)
    it("counts a document once under a node, however many of its paths lie there", function()
        local forest = source.tree({
            source.entry("1", "A (2000)", { { "web" }, { "web", "HTTP" }, { "web", "URI" } }),
            source.entry("2", "B (2001)", { { "web", "HTTP" } }),
        })
        assert.are.equal(2, subjects.total(forest[1]))
        assert.are.equal(2, subjects.total(forest[1].children[1]))
        assert.are.equal("|rfc-subjects-web|  web (2)", subjects.render(DOC, forest).lines[4])
    end)
    it("reads the contents block back into nodes: tag, slug, leaf, path and count", function()
        local nodes = subjects.read_nodes(doc.lines)
        assert.are.equal(13, #nodes)
        assert.are.same(
            { tag = "rfc-subjects-arpanet", slug = "arpanet", leaf = "arpanet", path = "ARPANET", count = 3 },
            nodes[1]
        )
        assert.are.same({
            tag = "rfc-subjects-data-formats-internationalization-character-sets-ascii",
            slug = "data-formats-internationalization-character-sets-ascii",
            leaf = "ascii",
            path = "data formats / internationalization / character sets / ASCII",
            count = 1,
        }, nodes[5])
    end)
    it("reads a name with its own parentheses, and nothing from a document with no contents", function()
        local forest =
            source.tree({ source.entry("341", "Taproot (Deployed)", { { "Layer", "Consensus (soft fork)" } }) })
        local nodes = subjects.read_nodes(subjects.render({ prefix = "bip", title = "t", about = "a" }, forest).lines)
        assert.are.same({
            tag = "bip-subjects-layer-consensus-soft-fork",
            slug = "layer-consensus-soft-fork",
            leaf = "consensus-soft-fork",
            path = "Layer / Consensus (soft fork)",
            count = 1,
        }, nodes[2])
        assert.are.same(
            {},
            subjects.read_nodes({ "*x-subjects.txt*  x  *x-subjects*", "about", "", "", help.MODELINE, help.FOOTER })
        )
        assert.are.equal(
            "tags-wot",
            subjects.read_nodes({
                "*w3c-subjects.txt*  x  *w3c-subjects*",
                "about",
                "",
                "|w3c-subjects-tags-wot|  WoT (11)",
            })[1].slug
        )
    end)
    it("renders an empty forest as the title, the about line and the footer", function()
        local d = subjects.render(DOC, {})
        assert.are.equal(6, #d.lines)
    end)
end)
