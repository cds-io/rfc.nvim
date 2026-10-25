local subjects = require("rfc.source.subjects")
local fixtures = require("spec.fixtures")

describe("entry", function()
    it("lists an entry under the paths no other path extends", function()
        local e = subjects.entry(
            "32",
            "HD Wallets (Deployed)",
            { { "Layer", "Applications" }, { "Layer" }, { "Type", "Informational" } }
        )
        assert.are.same({ { "Layer", "Applications" }, { "Type", "Informational" } }, e.direct)
        assert.are.equal("32", e.id)
    end)
end)

describe("rfc", function()
    local entries
    before_each(function()
        entries = subjects.rfc(fixtures.read(fixtures.rfc_tags))
    end)
    it("reads one entry per tagged row, the number without its prefix and the year in the label", function()
        assert.are.equal(9, #entries)
        assert.are.same({
            id = "791",
            label = "Internet Protocol (1981)",
            paths = { { "internet layer" }, { "internet layer", "IPv4" } },
            direct = { { "internet layer", "IPv4" } },
        }, entries[5])
    end)
    it("resolves each direct tag to the path that ends in it", function()
        assert.are.same({ { "messaging", "email", "mailing lists" }, { "ARPANET" } }, entries[3].direct)
    end)
    it("keeps a quoted title", function()
        assert.are.equal('Comments on "Socket Conventions Reconsidered" (1971)', entries[4].label)
    end)
    it("omits an untagged row", function()
        for _, e in ipairs(entries) do
            assert.are_not.equal("10053", e.id)
        end
    end)
    it("drops a tag that names no path and omits the entry when none is left", function()
        local got = subjects.rfc({
            "rfc,title,year,tags,paths",
            "RFC1,A,1969,ghost;NCP,ARPANET | ARPANET / NCP",
            "RFC2,B,1969,ghost,ARPANET",
        })
        assert.are.equal(1, #got)
        assert.are.same({ { "ARPANET", "NCP" } }, got[1].direct)
    end)
    it("passes a CSV error through", function()
        local got, err = subjects.rfc({ "rfc,title", 'RFC1,"open' })
        assert.is_nil(got)
        assert.are.equal("unterminated quote", err)
    end)
end)

describe("tree", function()
    local forest
    before_each(function()
        forest = subjects.tree(subjects.rfc(fixtures.read(fixtures.rfc_tags)))
    end)
    it("has every prefix as a node, roots sorted without regard to case", function()
        local names = {}
        for _, n in ipairs(forest) do
            table.insert(names, n.name)
        end
        assert.are.same({ "ARPANET", "data formats", "internet layer", "messaging", "web" }, names)
        assert.are.same(
            { "data formats", "internationalization", "character sets", "ASCII" },
            forest[2].children[1].children[1].children[1].path
        )
    end)
    it("puts the roots named in the order given first, the rest after by name", function()
        local ordered = subjects.tree(subjects.rfc(fixtures.read(fixtures.rfc_tags)), { "web", "messaging" })
        local names = {}
        for _, n in ipairs(ordered) do
            table.insert(names, n.name)
        end
        assert.are.same({ "web", "messaging", "ARPANET", "data formats", "internet layer" }, names)
    end)
    it("lists an entry under each of its direct paths, sorted by number", function()
        local ids = {}
        for _, e in ipairs(forest[1].entries) do
            table.insert(ids, e.id)
        end
        assert.are.same({ "37", "155", "175" }, ids)
        assert.are.equal("155", forest[4].children[1].children[1].entries[1].id)
        assert.are.same({}, forest[5].entries)
    end)
    it("is empty for no entries", function()
        assert.are.same({}, subjects.tree({}))
    end)
end)
