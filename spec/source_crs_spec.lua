local crs = require("rfc.source.crs")
local fp = require("cds.fp")
local fixtures = require("spec.fixtures")

local function extend(into, more)
    for _, l in ipairs(more) do
        table.insert(into, l)
    end
    return into
end

--- The two fixture pages joined as the source's index() joins the 32.
local function joined()
    local lines = { crs.marker("economic-policy") }
    extend(lines, fixtures.read(fixtures.crs_econ))
    table.insert(lines, crs.marker("national-defense"))
    return extend(lines, fixtures.read(fixtures.crs_defense))
end

local function by_id(entries, id)
    return fp.find(entries, function(e)
        return e.id == id
    end)
end

describe("topics", function()
    local topics
    before_each(function()
        topics = crs.topics(joined())
    end)
    it("answers one topic per page, in page order, named from the page's heading", function()
        assert.are.equal(2, #topics)
        assert.are.equal("economic-policy", topics[1].slug)
        assert.are.equal("Economic Policy", topics[1].name)
        assert.are.equal(6, #topics[1].entries)
        assert.are.equal("national-defense", topics[2].slug)
        assert.are.equal("National Defense", topics[2].name)
        assert.are.equal(3, #topics[2].entries)
    end)
    it("reads a revised report's number, id, title and both dates", function()
        assert.are.same({
            number = "R42853",
            id = "r42853",
            title = "Nuclear Energy: Overview of Congressional Issues",
            first = "2012-12-11",
            latest = "2026-10-22",
        }, by_id(topics[1].entries, "r42853"))
    end)
    it("reads a report never revised with its one date, a legacy number, and a title with an ampersand", function()
        local once = by_id(topics[1].entries, "r49489")
        assert.is_nil(once.first)
        assert.are.equal("2026-10-20", once.latest)
        local legacy = by_id(topics[1].entries, "98-35")
        assert.are.equal("98-35", legacy.number)
        assert.are.equal("2003-03-26", legacy.first)
        assert.are.equal(
            "The Federal Research and Development (R&D) Tax Credit",
            by_id(topics[1].entries, "r48848").title
        )
    end)
end)

describe("index", function()
    local entries
    before_each(function()
        entries = crs.index(joined())
    end)
    it("lists each report once with every topic that lists it", function()
        assert.are.equal(8, #entries)
        assert.are.same({ "Economic Policy", "National Defense" }, by_id(entries, "ib10051").topics)
        assert.are.same({ "National Defense" }, by_id(entries, "lsb11340").topics)
    end)
end)

describe("kind", function()
    it("reads the product from the number's prefix", function()
        assert.are.equal("Report", crs.kind("R42853"))
        assert.are.equal("Report", crs.kind("RL33110"))
        assert.are.equal("Report", crs.kind("RS20000"))
        assert.are.equal("In Focus", crs.kind("IF13249"))
        assert.are.equal("Insight", crs.kind("IN11374"))
        assert.are.equal("Legal Sidebar", crs.kind("LSB11340"))
    end)
    it("files the numbered and lettered legacy series, and junk, as Legacy", function()
        assert.are.equal("Legacy", crs.kind("98-446RSH"))
        assert.are.equal("Legacy", crs.kind("IB10051"))
        assert.are.equal("Legacy", crs.kind("ZZZ58CA"))
    end)
end)

describe("dates", function()
    it("reads the page's long date as ISO and writes it back", function()
        assert.are.equal("2026-10-22", crs.date("October 22, 2026"))
        assert.are.equal("2016-03-09", crs.date("March 9, 2016"))
        assert.is_nil(crs.date("not a date"))
        assert.are.equal("March 9, 2016", crs.long_date("2016-03-09"))
    end)
end)

local function json(fixture)
    return table.concat(fixtures.read(fixture), "\n")
end

describe("version", function()
    it("reads the newest version's facts and links from a report's record", function()
        assert.are.same({
            number = "R43397",
            date = "2026-10-27",
            count = 17,
            first = "2016-03-09",
            html = "files/2026-10-27_R43397_e500edbb9a8b94251f7ace20fe27473d9263bf3a.html",
            mirror = "files/2026-10-27_R43397_264c73e065f072820bff571bfe73b61cc114f9fc.pdf",
            pdf = "https://www.congress.gov/crs_external_products/R/PDF/R43397/R43397.37.pdf",
            source = "https://www.congress.gov/crs-product/R43397",
            topics = { "Appropriations" },
        }, crs.version(json(fixtures.crs_r43397_json)))
    end)
    it("reads a one-version record", function()
        local v = crs.version(json(fixtures.crs_if12345_json))
        assert.are.equal("IF12345", v.number)
        assert.are.equal(1, v.count)
        assert.are.equal("2023-03-14", v.date)
        assert.are.equal("2023-03-14", v.first)
        assert.are.equal("files/2023-03-14_IF12345_1087fe4e8af95026423404068d5a04b79a489c4f.html", v.html)
        assert.are.equal("https://crsreports.congress.gov/product/pdf/IF/IF12345/1", v.pdf)
        assert.are.same({ "National Defense" }, v.topics)
    end)
    it("refuses a text that is not a record", function()
        local v, err = crs.version("<html>404</html>")
        assert.is_nil(v)
        assert.are.equal("not a CRS report record", err)
    end)
    it("answers no html when the newest version lists no HTML format", function()
        local text = json(fixtures.crs_if12345_json):gsub('{%s*\n%s*"format": "HTML".-}', "")
        local v = crs.version(text)
        assert.is_nil(v.html)
        assert.are.equal("https://crsreports.congress.gov/product/pdf/IF/IF12345/1", v.pdf)
    end)
end)

describe("facts", function()
    it("writes one comment line and reads it back", function()
        local line = crs.facts(crs.version(json(fixtures.crs_r43397_json)))
        assert.are.equal(
            "<!-- crs: id=R43397 versions=17 first=2016-03-09 topics=Appropriations"
                .. " pdf=https://www.congress.gov/crs_external_products/R/PDF/R43397/R43397.37.pdf"
                .. " mirror=files/2026-10-27_R43397_264c73e065f072820bff571bfe73b61cc114f9fc.pdf"
                .. " source=https://www.congress.gov/crs-product/R43397 -->",
            line
        )
        assert.are.same({
            id = "R43397",
            versions = 17,
            first = "2016-03-09",
            topics = { "Appropriations" },
            pdf = "https://www.congress.gov/crs_external_products/R/PDF/R43397/R43397.37.pdf",
            mirror = "files/2026-10-27_R43397_264c73e065f072820bff571bfe73b61cc114f9fc.pdf",
            source = "https://www.congress.gov/crs-product/R43397",
        }, crs.read_facts(line))
    end)
    it("omits a missing link and joins several topics with semicolons", function()
        local line = crs.facts({ number = "X1", count = 2, first = "2001-01-01", topics = { "A", "B C" } })
        assert.are.equal("<!-- crs: id=X1 versions=2 first=2001-01-01 topics=A;B C -->", line)
        assert.are.same({ "A", "B C" }, crs.read_facts(line).topics)
        assert.is_nil(crs.read_facts(line).pdf)
    end)
    it("is nil for any other line", function()
        assert.is_nil(crs.read_facts("<div><p></p>"))
    end)
end)

describe("mentions", function()
    local function ids(line)
        return fp.map(crs.mentions(line), function(m)
            return m.id
        end)
    end
    it("finds the product forms", function()
        assert.are.same({ "r43397" }, ids("See CRS Report R43397, Legislative Branch Appropriations."))
        assert.are.same({ "rl33110" }, ids("CRS Report RL33110"))
        assert.are.same({ "if12345" }, ids("CRS In Focus IF12345"))
        assert.are.same({ "in11374" }, ids("CRS Insight IN11374"))
        assert.are.same({ "lsb11340" }, ids("CRS Legal Sidebar LSB11340"))
        assert.are.same({ "if12345" }, ids("CRS Report IF12345"))
    end)
    it("finds the legacy numbered form only after CRS Report", function()
        assert.are.same({ "97-1011" }, ids("For a list, see CRS Report 97-1011, Salaries of Members."))
        assert.are.same({}, ids("P.L. 97-1011 and section 98-684 are not reports."))
    end)
    it("carries the byte range of the whole citation", function()
        local line = "x CRS Report R43397 y"
        local m = crs.mentions(line)[1]
        assert.are.equal("crs", m.kind)
        assert.are.equal("CRS Report R43397", line:sub(m.first, m.last))
    end)
    it("finds a number with a letter suffix, as the legacy series and the IP series spell them", function()
        assert.are.same({ "98-446rsh", "96-212enr" }, ids("CRS Report 98-446RSH and CRS Report 96-212ENR"))
        assert.are.same({ "ip0333a" }, ids("CRS Report IP0333A"))
        assert.are.same({ "r43397" }, ids("CRS Report R43397, Legislative Branch"))
    end)
    it("finds two on one line in order", function()
        assert.are.same({ "r43397", "if12345" }, ids("CRS Report R43397 and CRS In Focus IF12345"))
    end)
end)

describe("normalize over the R43397 excerpt", function()
    local out, head, text
    before_each(function()
        out, head = crs.normalize(fixtures.read(fixtures.crs_r43397))
        text = table.concat(out, "\n")
    end)
    it("reads the head and removes the header and the contents lists", function()
        assert.are.same({
            title = "Legislative Branch Appropriations: Frequently Asked Questions",
            updated = "Updated October 27, 2026",
            number = "R43397",
        }, head)
        assert.is_nil(text:find("ReportHeader", 1, true))
        assert.is_nil(text:find("Jump to Main Text", 1, true))
        assert.is_nil(text:find("<h2>Contents</h2>", 1, true))
        assert.is_nil(text:find("<h2>Figures</h2>", 1, true))
        assert.is_nil(text:find("<h2>Tables</h2>", 1, true))
        assert.is_not_nil(text:find(">Summary</h2>", 1, true))
    end)
    it("gives every heading an id from its anchors, the one before it or the first inside it", function()
        assert.is_not_nil(text:find('<h2 id="Summary">Summary</h2>', 1, true))
        assert.is_not_nil(text:find('<h4 id="_Toc390952393">In addition to the Senate', 1, true))
        assert.is_not_nil(text:find('<h4 id="_Toc390952390">What percentage of total budget', 1, true))
        assert.is_nil(text:find("_Hlk227054554", 1, true))
        assert.is_not_nil(text:find(">Frequently Asked Questions</h2>", 1, true))
    end)
    it("turns the remaining named anchors into ids", function()
        assert.is_not_nil(text:find('id="fn1"', 1, true))
        assert.is_nil(text:find("<a name=", 1, true))
    end)
    it("links a citation to its tag and brackets a footnote mark", function()
        assert.is_not_nil(text:find('<a href="rfc-tag:crs-97-1011">CRS Report 97-1011</a>', 1, true))
        assert.is_not_nil(text:find('<sup><a href="#fn1" id="ifn1">[1]</a></sup>', 1, true))
    end)
    it("removes an empty image", function()
        assert.is_nil(text:find("<img>", 1, true))
    end)
end)

describe("normalize over citations already inside a link", function()
    local function one(html)
        return table.concat((crs.normalize({ html })), "\n")
    end
    it("puts the tag on an enclosing link that has no destination, as pymupdf wraps a PDF link", function()
        assert.are.equal(
            '<p>See <a href="rfc-tag:crs-r43397"><span>CRS Report R43397</span></a>.</p>',
            one("<p>See <a><span>CRS Report R43397</span></a>.</p>")
        )
    end)
    it("leaves a citation inside a link with a destination alone", function()
        local html = '<p>See <a href="https://crsreports.congress.gov/x">CRS Report R43397</a>.</p>'
        assert.are.equal(html, one(html))
    end)
    it("still links a bare citation and one beside a link", function()
        assert.are.equal(
            '<p><a href="rfc-tag:crs-if12345">CRS In Focus IF12345</a> and <a href="#x">y</a> and'
                .. ' <a href="rfc-tag:crs-97-1011">CRS Report 97-1011</a></p>',
            one('<p>CRS In Focus IF12345 and <a href="#x">y</a> and CRS Report 97-1011</p>')
        )
    end)
end)

describe("normalize over a text without a header", function()
    it("answers the lines and an empty head", function()
        local out, head = crs.normalize({ "<div><h2>Summary</h2><p>Hi</p></div>" })
        assert.are.same({ title = "", updated = "", number = "" }, head)
        assert.are.equal(1, #out)
    end)
end)
