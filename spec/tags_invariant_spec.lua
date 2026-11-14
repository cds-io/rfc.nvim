-- The invariant the tags file leans on: every render's declared tags are the
-- tags its lines carry, name and line alike, so the store writes a
-- document's entries from what the render declared and never scans the text.
local help = require("rfc.help")
local tags = require("rfc.help.tags")
local fixtures = require("spec.fixtures")

before_each(function()
    tags.set_shortnames({ "w3c", "crs" })
end)
after_each(function()
    tags.set_shortnames({})
end)

local function sorted(list)
    local out = {}
    for _, t in ipairs(list) do
        out[#out + 1] = t.name .. ":" .. t.line
    end
    table.sort(out)
    return out
end

--- A CRS report's stored text: the fact line, then the mirror's HTML.
local function crs_raw()
    local crs = require("rfc.sources.crs.reader")
    local v = crs.version(table.concat(fixtures.read(fixtures.crs_r43397_json), "\n"))
    local lines = { crs.facts(v) }
    for _, l in ipairs(fixtures.read(fixtures.crs_r43397)) do
        table.insert(lines, l)
    end
    return lines
end

local CASES = {
    {
        "RFC 9110",
        function()
            return require("rfc.sources.rfc.render").render("9110", fixtures.read(fixtures.rfc9110))
        end,
    },
    {
        "RFC 2616",
        function()
            return require("rfc.sources.rfc.render").render("2616", fixtures.read(fixtures.rfc2616))
        end,
    },
    {
        "ERC-20",
        function()
            return require("rfc.sources.eip.render").render("20", fixtures.read(fixtures.erc20))
        end,
    },
    {
        "EIP-1559",
        function()
            return require("rfc.sources.eip.render").render("1559", fixtures.read(fixtures.eip1559))
        end,
    },
    {
        "BIP-32",
        function()
            return require("rfc.sources.bip.render").render("32", fixtures.read(fixtures.bip32))
        end,
    },
    {
        "SIMD-64",
        function()
            return require("rfc.sources.simd.render").render("64", fixtures.read(fixtures.simd64))
        end,
    },
    {
        "W3C css-grid-2",
        function()
            return require("rfc.sources.w3c.render").render(
                "css-grid-2",
                fixtures.read(fixtures.w3c_grid),
                "https://www.w3.org/TR/css-grid-2/"
            )
        end,
    },
    {
        "W3C wot-thing-description11",
        function()
            return require("rfc.sources.w3c.render").render(
                "wot-thing-description11",
                fixtures.read(fixtures.w3c_td),
                "https://www.w3.org/TR/wot-thing-description11/"
            )
        end,
    },
    {
        "CRS R43397",
        function()
            return require("rfc.format.report").render_model(
                require("rfc.sources.crs.model").model("r43397", crs_raw())
            )
        end,
    },
    {
        "the RFC subjects",
        function()
            local source = require("rfc.source.subjects")
            local forest = source.tree(source.rfc(fixtures.read(fixtures.rfc_tags)))
            return require("rfc.subjects").render({ prefix = "rfc", title = "RFCs by subject", about = "a" }, forest)
        end,
    },
}

describe("a render's declared tags", function()
    for _, case in ipairs(CASES) do
        it("are the tags its lines carry: " .. case[1], function()
            local doc = case[2]()
            assert.is_true(#doc.tags > 0)
            assert.are.same(sorted(doc.tags), sorted(help.tags_in(doc.lines)))
        end)
    end
end)
