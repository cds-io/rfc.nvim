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
        assert.are.equal(2, #topics[2].entries)
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
        assert.are.equal(7, #entries)
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
