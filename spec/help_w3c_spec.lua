local help_w3c = require("rfc.help_w3c")
local help = require("rfc.help")
local outline = require("rfc.outline")
local fp = require("cds.fp")
local fixtures = require("spec.fixtures")

local TD = "https://www.w3.org/TR/wot-thing-description11/"

describe("link", function()
    it("writes a tag mention as the tag itself", function()
        local text = require("rfc.help.w3c.text")
        local t = {
            text = "See CRS Report 97-1011.",
            mentions = { { kind = "tag", id = "crs-97-1011", first = 5, last = 22 } },
        }
        assert.are.equal("See |crs-97-1011|.", text.link(t, {}))
    end)
end)

describe("wrap", function()
    it("wraps at spaces within the width, keeping the indent and never splitting a tag", function()
        assert.are.same({ "    aaa bbb", "    ccc" }, help_w3c.wrap("aaa bbb ccc", "    ", 11))
        assert.are.same(
            { "x", "|w3c-a#1.2.3.4.5.6.7.8.9|", "y" },
            help_w3c.wrap("x |w3c-a#1.2.3.4.5.6.7.8.9| y", "", 10)
        )
    end)
    it("keeps a hard break", function()
        assert.are.same({ "a b", "c" }, help_w3c.wrap("a b\nc", "", 78))
    end)
end)

describe("render over the Thing Description excerpt", function()
    local doc, lines
    before_each(function()
        doc = help_w3c.render("wot-thing-description11", fixtures.read(fixtures.w3c_td), TD)
        lines = doc.lines
    end)
    it("writes the title line with the file tags, the subtitle, the metadata and the abstract", function()
        assert.are.equal(
            help.with_tag(
                "*w3c-wot-thing-description11.txt*  Web of Things (WoT) Thing Description 1.1",
                "w3c-wot-thing-description11"
            ),
            lines[1]
        )
        assert.is_truthy(lines[2]:match("^W3C Recommendation"))
        assert.is_not_nil((fp.find(lines, function(l)
            return l:match("^This version: https://www%.w3%.org/TR/2023/") ~= nil
        end)))
        assert.is_not_nil((fp.find(lines, function(l)
            return help.section_tag(l) == "w3c-wot-thing-description11#abstract"
        end)))
    end)
    it("writes the contents block with one row per heading, indented by level, then tagged headings", function()
        assert.is_not_nil((fp.find(lines, function(l)
            return l:match("^  |w3c%-wot%-thing%-description11#1%.1|  1%.1 ") ~= nil
        end)))
        local h = fp.find(lines, function(l)
            return help.section_tag(l) == "w3c-wot-thing-description11#1.1"
        end)
        assert.is_truthy(h and h:match("^1%.1 "))
        assert.is_not_nil((fp.find(doc.tags, function(t)
            return t.name == "w3c-wot-thing-description11#abstract"
        end)))
    end)
    it(
        "renders a figure as caption, alt and absolute URL, a callout as a ~ line over an indented body, code fenced",
        function()
            assert.is_not_nil((fp.find(lines, function(l)
                return l:match("^Figure %d+: .* ~$") ~= nil
            end)))
            assert.is_not_nil((fp.find(lines, function(l)
                return l == "    https://www.w3.org/TR/wot-thing-description11/visualization/td.png"
            end)))
            assert.is_not_nil((fp.find(lines, function(l)
                return l:match("^Example 1: .* ~$") ~= nil
            end)))
            assert.is_not_nil((fp.find(lines, function(l)
                return l == ">json"
            end)))
        end
    )
    it("renders a table with its caption line and the aligned layout", function()
        local i = fp.find(lines, function(l)
            return l:match("^Table 1: .* ~$") ~= nil
        end)
        assert.is_not_nil(i)
    end)
    it("links a section, a report and a reference", function()
        assert.is_not_nil((fp.find(lines, function(l)
            return l:find("|w3c-wot-architecture11|", 1, true) ~= nil
        end)))
        assert.is_not_nil((fp.find(lines, function(l)
            return l:find("|w3c-wot-thing-description11#ref-", 1, true) ~= nil
        end)))
        assert.is_not_nil((fp.find(doc.tags, function(t)
            return t.name:match("^w3c%-wot%-thing%-description11#ref%-") ~= nil
        end)))
    end)
    it("declares exactly the tags tags_in reads back, and gives the outline its levels", function()
        local names = fp.map(help.tags_in(lines), function(t)
            return t.name
        end)
        local declared = fp.map(doc.tags, function(t)
            return t.name
        end)
        table.sort(names)
        table.sort(declared)
        assert.are.same(declared, names)
        local headings = outline.of(lines)
        assert.is_true(#headings > 5)
        local h = fp.find(headings, function(x)
            return x.tag == "w3c-wot-thing-description11#1.1"
        end)
        assert.are.equal(2, h and h.level)
    end)
    it("numbers a repeated unnumbered heading's tag", function()
        local d = help_w3c.render(
            "x",
            { "<h1>X</h1><h2>Examples</h2><p>a</p><h2>Examples</h2><p>b</p>" },
            "https://www.w3.org/TR/x/"
        )
        assert.is_not_nil((fp.find(d.tags, function(t)
            return t.name == "w3c-x#examples-2"
        end)))
    end)
    it("keeps a code block whose first line is empty and whose text had entities", function()
        local d =
            help_w3c.render("x", { "<h1>X</h1><pre><code>", "&lt;a&gt;</code></pre>" }, "https://www.w3.org/TR/x/")
        assert.is_not_nil((fp.find(d.lines, function(l)
            return l == ">"
        end)))
        assert.is_not_nil((fp.find(d.lines, function(l)
            return l == "    <a>"
        end)))
    end)
end)

describe("render over the Grid excerpt", function()
    it("renders a Bikeshed report: numbered headings, a note, wrapped paragraphs", function()
        local lines =
            help_w3c.render("css-grid-2", fixtures.read(fixtures.w3c_grid), "https://www.w3.org/TR/css-grid-2/").lines
        assert.is_not_nil((fp.find(lines, function(l)
            return l == "Note ~"
        end)))
        assert.is_not_nil((fp.find(lines, function(l)
            return help.section_tag(l) == "w3c-css-grid-2#1"
        end)))
        local long = fp.filter(lines, function(l)
            return #l > 78
                and not (
                    l:match("^>")
                    or l:match("^    ")
                    or l:match("%*w3c%-")
                    or l:match("^%s*|")
                    or l:match("^  %S.*  %S")
                )
        end)
        assert.are.same({}, long)
    end)
end)

describe("render over small report shapes", function()
    it("links a section by the section's id and by its heading's, as ReSpec writes both", function()
        local doc = help_w3c.render("x", {
            '<section id="introduction"><h2 id="x1-introduction"><bdi class="secno">1. </bdi>Introduction</h2>',
            '<p>See <a href="#introduction">the intro</a> and <a href="#x1-introduction">again</a>.</p></section>',
        }, "https://www.w3.org/TR/x/")
        assert.is_not_nil((fp.find(doc.lines, function(l)
            return l == "See |w3c-x#1| and |w3c-x#1|."
        end)))
    end)
    it("slugs a section number that is words, so the tag has no spaces", function()
        local doc = help_w3c.render("x", {
            '<section id="non-text-content"><h4><span class="secno">Success Criterion 1.1.1</span> Non-text Content</h4>',
            '<p>See <a href="#non-text-content">it</a>.</p></section>',
        }, "https://www.w3.org/TR/x/")
        assert.is_not_nil((fp.find(doc.tags, function(t)
            return t.name == "w3c-x#success-criterion-1.1.1"
        end)))
        assert.is_not_nil((fp.find(doc.lines, function(l)
            return l == "See |w3c-x#success-criterion-1.1.1|."
        end)))
        assert.is_not_nil((fp.find(help.tags_in(doc.lines), function(t)
            return t.name == "w3c-x#success-criterion-1.1.1"
        end)))
    end)
    it("makes a figure's URL absolute with one slash whether or not the report's URL ends in one", function()
        for _, url in ipairs({ "https://www.w3.org/TR/x/", "https://www.w3.org/TR/x" }) do
            local doc = help_w3c.render("x", { '<figure><img src="a.png" alt="A"></figure>' }, url)
            assert.is_not_nil((fp.find(doc.lines, function(l)
                return l == "    https://www.w3.org/TR/x/a.png"
            end)), url)
        end
    end)
end)
