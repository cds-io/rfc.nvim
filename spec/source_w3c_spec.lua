local w3c = require("rfc.source.w3c")
local fp = require("cds.fp")
local fixtures = require("spec.fixtures")

describe("index", function()
    local entries
    before_each(function()
        entries = w3c.index(fixtures.read(fixtures.w3c_tr))
    end)
    it("reads one entry per shortname with its facts", function()
        local td = fp.find(entries, function(e)
            return e.id == "wot-thing-description11"
        end)
        assert.are.same({
            shortname = "wot-thing-description11",
            id = "wot-thing-description11",
            url = "https://www.w3.org/TR/wot-thing-description11/",
            title = "Web of Things (WoT) Thing Description 1.1",
            date = "2023-12-05",
            maturity = "Standard",
            tags = { "WoT" },
            groups = { "Web of Things Working Group" },
        }, td)
    end)
    it("keeps the first of a duplicated shortname, lowercases the id and keeps the URL's spelling", function()
        assert.are.equal(1, #fp.filter(entries, function(e)
            return e.id == "performance-timeline"
        end))
        local w = fp.find(entries, function(e)
            return e.id == "wcag22"
        end)
        assert.are.equal("WCAG22", w.shortname)
        assert.are.equal("https://www.w3.org/TR/WCAG22/", w.url)
    end)
    it("reads a row without tags, without a maturity, and a NOTE URL without a slash", function()
        local n = fp.find(entries, function(e)
            return e.url:match("/TR/NOTE%-") ~= nil
        end)
        assert.is_truthy(n)
        assert.is_not_nil((fp.find(entries, function(e)
            return #e.tags == 0
        end)))
        assert.is_not_nil((fp.find(entries, function(e)
            return e.maturity == ""
        end)))
    end)
    it("reads every maturity the page uses", function()
        local seen = fp.set(fp.map(entries, function(e)
            return e.maturity
        end))
        for _, m in ipairs({
            "Standard",
            "Draft Standard",
            "Candidate Standard",
            "Note",
            "Draft Note",
            "Draft Registry",
            "Statement",
        }) do
            assert.is_true(seen[m], m)
        end
    end)
end)

describe("short_group", function()
    it("writes a group's kind as the W3C's own shorthand, and leaves any other name alone", function()
        assert.are.equal(
            "Cascading Style Sheets (CSS) WG",
            w3c.short_group("Cascading Style Sheets (CSS) Working Group")
        )
        assert.are.equal("Digital Publishing IG", w3c.short_group("Digital Publishing Interest Group"))
        assert.are.equal("Solid CG", w3c.short_group("Solid Community Group"))
        assert.are.equal("Web Payments BG", w3c.short_group("Web Payments Business Group"))
        assert.are.equal("Technical Architecture Group", w3c.short_group("Technical Architecture Group"))
        assert.are.equal("Advisory Board", w3c.short_group("Advisory Board"))
    end)
end)

describe("times", function()
    it("turns an index date into a time and back, and reads and writes HTTP dates", function()
        assert.are.equal(
            "Mon, 04 Dec 2023 05:07:44 GMT",
            w3c.http_time(w3c.parse_http_time("Mon, 04 Dec 2023 05:07:44 GMT"))
        )
        assert.is_true(w3c.date_time("2023-12-05") > w3c.parse_http_time("Mon, 04 Dec 2023 05:07:44 GMT"))
        assert.is_nil(w3c.parse_http_time("yesterday"))
    end)
end)
