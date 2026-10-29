local model = require("rfc.help.crs.model")
local help_w3c = require("rfc.help_w3c")
local document = require("rfc.document")
local crs = require("rfc.source.crs")
local help = require("rfc.help")
local fp = require("cds.fp")
local fixtures = require("spec.fixtures")

--- The stored text as the fetch writes it: the fact line, then the HTML.
local function raw()
    local v = crs.version(table.concat(fixtures.read(fixtures.crs_r43397_json), "\n"))
    local lines = { crs.facts(v) }
    for _, l in ipairs(fixtures.read(fixtures.crs_r43397)) do
        table.insert(lines, l)
    end
    return lines
end

--- The stored text of a report the mirror rendered from its PDF with a text
--- extractor: the fact line, then one line a break and no block element.
local function dumped()
    local v = crs.version(table.concat(fixtures.read(fixtures.crs_r43397_json), "\n"))
    local lines = { crs.facts(v), "<div><b>Title</b><br/>" }
    for i = 1, 40 do
        table.insert(lines, ("line %d of the report <br/>"):format(i))
    end
    table.insert(lines, "</div>")
    return lines
end

local SUBTITLE = "CRS Report R43397 · Updated October 27, 2026 · 17 versions since March 9, 2016"

describe("model", function()
    it("names the document, its URL and its head from the fact line and the header", function()
        local m = model.model("r43397", raw())
        assert.are.equal("html", m.kind)
        assert.are.equal("crs-r43397", m.name)
        assert.are.equal("r43397", m.id)
        assert.are.equal("https://www.everycrsreport.com/reports/R43397.html", m.url)
        assert.are.equal("Legislative Branch Appropriations: Frequently Asked Questions", m.head.title)
        assert.are.equal(SUBTITLE, m.head.subtitle)
        assert.are.same(
            { "Topics", "PDF", "Mirror PDF", "Source" },
            fp.map(m.head.meta, function(e)
                return e.term
            end)
        )
        assert.are.equal("Appropriations", m.head.meta[1].text.text)
        assert.are.equal(
            "https://www.everycrsreport.com/files/2026-10-27_R43397_264c73e065f072820bff571bfe73b61cc114f9fc.pdf",
            m.head.meta[3].text.text
        )
        assert.are.same({}, m.head.abstract)
        assert.is_nil(m.lines[1]:match("^<!%-%- crs:"))
    end)
    it("tags the headings through their ids", function()
        local m = model.model("r43397", raw())
        assert.are.equal("crs-r43397#summary", m.sections.Summary)
        assert.is_not_nil(m.sections._Toc390952393)
        assert.are.same({}, m.refs)
    end)
    it("renders without a fact line", function()
        local m = model.model("r43397", fixtures.read(fixtures.crs_r43397))
        assert.are.equal("CRS Report R43397 · Updated October 27, 2026", m.head.subtitle)
        assert.are.same({}, m.head.meta)
        assert.are.equal("https://www.everycrsreport.com/reports/R43397.html", m.url)
        assert.is_table(help_w3c.render_model(m).lines)
    end)
    it("says one version for a report never revised", function()
        local lines =
            { crs.facts({ number = "IF12345", count = 1, first = "2023-03-14", topics = { "National Defense" } }) }
        for _, l in ipairs(fixtures.read(fixtures.crs_r43397)) do
            table.insert(lines, l)
        end
        local m = model.model("if12345", lines)
        assert.are.equal("CRS In Focus IF12345 · Updated October 27, 2026 · 1 version", m.head.subtitle)
        assert.are.same(
            { "Topics" },
            fp.map(m.head.meta, function(e)
                return e.term
            end)
        )
    end)
end)

describe("the help render", function()
    local lines
    before_each(function()
        lines = help_w3c.render_model(model.model("r43397", raw())).lines
    end)
    it("writes the title line, the subtitle, the citation as a tag and the summary's tag", function()
        assert.are.equal(
            help.with_tag(
                "*crs-r43397.txt*  Legislative Branch Appropriations: Frequently Asked Questions",
                "crs-r43397"
            ),
            lines[1]
        )
        assert.are.equal(SUBTITLE, lines[2])
        assert.is_not_nil((fp.find(lines, function(l)
            return l:find("|crs-97-1011|", 1, true) ~= nil
        end)))
        assert.is_not_nil((fp.find(lines, function(l)
            return help.section_tag(l) == "crs-r43397#summary"
        end)))
    end)
end)

--- The number of the first line holding `text`, or nil.
local function index_of(lines, text)
    for i, l in ipairs(lines) do
        if l:find(text, 1, true) then
            return i
        end
    end
    return nil
end

describe("a report handed over as a text dump", function()
    it("opens the help view with a callout naming the PDF, before the body", function()
        local lines = help_w3c.render_model(model.model("r43397", dumped())).lines
        local label = index_of(lines, "Upstream conversion error ~")
        assert.is_number(label)
        local text = table.concat(lines, "\n", label)
        assert.is_not_nil(text:find("Upstream (at source) conversion error.", 1, true))
        assert.is_not_nil(
            text:find("https://www.congress.gov/crs_external_products/R/PDF/R43397/R43397.37.pdf", 1, true)
        )
        assert.is_true(label < index_of(lines, "line 1 of the report"))
    end)
    it("says so in the Markdown document too", function()
        local markdown = table.concat(document.from_model(model.model("r43397", dumped())).markdown, "\n")
        assert.is_not_nil(markdown:find("Upstream (at source) conversion error.", 1, true))
    end)
    it("warns nothing over a report with paragraphs", function()
        local lines = help_w3c.render_model(model.model("r43397", raw())).lines
        assert.is_nil((fp.find(lines, function(l)
            return l:find("Upstream conversion error", 1, true) ~= nil
        end)))
    end)
end)

describe("the Markdown document", function()
    it("anchors the headings and links the citation", function()
        local doc = document.from_model(model.model("r43397", raw()))
        assert.are.equal(1, doc.anchors["crs-r43397"])
        assert.is_number(doc.anchors["crs-r43397#summary"])
        assert.is_not_nil((fp.find(doc.headings, function(h)
            return h.tag == "crs-r43397#summary"
        end)))
        assert.is_not_nil(table.concat(doc.markdown, "\n"):find("(rfc-tag:crs-97-1011)", 1, true))
    end)
    it("carries the head: the title, the subtitle and the links back to the original", function()
        local doc = document.from_model(model.model("r43397", raw()))
        local markdown = table.concat(doc.markdown, "\n")
        assert.is_not_nil(markdown:find("Legislative Branch Appropriations: Frequently Asked Questions", 1, true))
        assert.is_not_nil(markdown:find(SUBTITLE, 1, true))
        assert.is_not_nil(
            markdown:find("https://www.congress.gov/crs_external_products/R/PDF/R43397/R43397.37.pdf", 1, true)
        )
        assert.is_not_nil(markdown:find("https://www.congress.gov/crs-product/R43397", 1, true))
        assert.is_not_nil(markdown:find("Appropriations", 1, true))
        -- the head sits before the body
        assert.is_true(markdown:find(SUBTITLE, 1, true) < markdown:find("Summary", 1, true))
    end)
    it("says what the header alone says when there is no fact line", function()
        local doc = document.from_model(model.model("r43397", fixtures.read(fixtures.crs_r43397)))
        local markdown = table.concat(doc.markdown, "\n")
        assert.is_not_nil(markdown:find("CRS Report R43397 · Updated October 27, 2026", 1, true))
        assert.is_nil(markdown:find("PDF", 1, true))
    end)
end)
