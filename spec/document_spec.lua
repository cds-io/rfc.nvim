local contract = require("rfc.document")
local document = require("cds.document")
local fixtures = require("spec.fixtures")

describe("RFC shared document adapters", function()
    it("preserves RFC section and citation tags in Markdown", function()
        local exported = require("rfc.help").render("9110", fixtures.read(fixtures.rfc9110))
        local doc = contract.from_help(exported.lines)
        assert.matches("Resources", doc.markdown[assert(doc.anchors["rfc9110-3.1"])])
        assert.equals(1, doc.anchors.rfc9110)
        local found = false
        for _, link in ipairs(doc.links) do
            if link.target == "rfc-tag:rfc2616-14.4" then
                found = true
            end
        end
        assert.is_true(found)
        assert.equals(#require("rfc.outline").of(exported.lines), #doc.headings)
    end)

    it("keeps proposal alias tags, code and cross-source references", function()
        local doc = contract.from_help(require("rfc.help_eip").render("20", fixtures.read(fixtures.erc20)).lines)
        assert.equals(1, doc.anchors.erc20)
        assert.equals(doc.anchors.eip20, doc.anchors.erc20)
        assert.is_not_nil(doc.anchors["eip20-abstract"])
        assert.truthy(table.concat(doc.markdown, "\n"):find("```", 1, true))
    end)

    it("retains W3C native HTML IDs and numbered RFC tags at the same heading", function()
        local doc = contract.report("css-grid-2", fixtures.read(fixtures.w3c_grid), "https://www.w3.org/TR/css-grid-2/")
        assert.equals(doc.anchors.intro, doc.anchors["w3c-css-grid-2#1"])
        assert.matches("Introduction", doc.markdown[assert(document.anchor(doc, "intro"))])
        assert.is_not_nil(doc.anchors["w3c-css-grid-2#1.1"])
        assert.is_true(#doc.links > 0)
        assert.truthy(table.concat(doc.markdown, "\n"):find("!%["))
    end)

    it("keeps subject tags navigable without leaking help modelines or render footers", function()
        local doc = contract.from_help({
            "*rfc-subjects.txt*  Subjects *rfc-subjects*",
            "Web *rfc-subjects-web*",
            "|rfc9110| HTTP",
            " vim:tw=78:ft=help:",
            " rfc.nvim render v1",
        })
        assert.equals(2, doc.anchors["rfc-subjects-web"])
        assert.equals("rfc-tag:rfc9110", doc.links[1].target)
        assert.equals(3, #doc.markdown)
    end)
    it("removes only known help declarations and preserves wildcard and note prose", function()
        local lines = {
            "*rfc1.txt* Example *rfc1*",
            "Accept: */*",
            "A *Note:* is meaningful.",
            "Literal *not-a-tag* and |rfc2|.",
            ">http",
            "Accept: */*",
            "<",
        }
        local doc = contract.from_help(lines)
        assert.equals("# Example", doc.markdown[1])
        assert.equals("Accept: \\*/\\*", doc.markdown[2])
        assert.equals("A \\*Note:\\* is meaningful.", doc.markdown[3])
        assert.equals("Literal \\*not-a-tag\\* and [rfc2](rfc-tag:rfc2).", doc.markdown[4])
        assert.equals("Accept: */*", doc.markdown[6])
        assert.equals("Accept: */*", lines[2])
        assert.equals(1, doc.anchors.rfc1)
    end)

    it("retains every MIME wildcard in the RFC 9110 fixture", function()
        local exported = require("rfc.help").render("9110", fixtures.read(fixtures.rfc9110))
        local doc = contract.from_help(exported.lines)
        local original = table.concat(exported.lines, "\n")
        local decoded = table.concat(doc.markdown, "\n"):gsub("\\(%p)", "%1")
        local _, before = original:gsub("%*/%*", "")
        local _, after = decoded:gsub("%*/%*", "")
        assert.equals(7, before)
        assert.equals(before, after)
        local direct = table.concat(contract.from_model(exported.model).markdown, "\n"):gsub("\\(%p)", "%1")
        local _, direct_count = direct:gsub("%*/%*", "")
        assert.equals(before, direct_count)
    end)
    it("shares source tag plans between native help and Markdown without mutating inputs", function()
        local cases = {
            { require("rfc.help"), "9110", fixtures.rfc9110 },
            { require("rfc.help_eip"), "20", fixtures.erc20 },
            { require("rfc.help_bip"), "32", fixtures.bip32 },
            { require("rfc.help_simd"), "64", fixtures.simd64 },
            { require("rfc.help_w3c"), "css-grid-2", fixtures.w3c_grid, "https://www.w3.org/TR/css-grid-2/" },
        }
        for _, case in ipairs(cases) do
            local lines = fixtures.read(case[3])
            local original = table.concat(lines, "\n")
            local exported = case[1].render(case[2], lines, case[4])
            local plan = assert(exported.model)
            local name, first_block = plan.name, plan.blocks[1]
            local source = contract.from_model(plan)
            assert.equals(1, source.anchors[name])
            for _, heading in ipairs(require("rfc.outline").of(exported.lines)) do
                assert.is_not_nil(source.anchors[heading.tag], heading.tag)
            end
            assert.equals(name, plan.name)
            assert.is_true(first_block == plan.blocks[1])
            assert.equals(original, table.concat(lines, "\n"))
        end
    end)

    it("renders repeated proposal headings and literal wildcard prose directly from a source plan", function()
        local spec = require("rfc.help_eip").spec
        local lines =
            { "---", "title: Literal", "---", "# Same", "Accept: `*/*`", "# Same", "```http", "Accept: */*", "```" }
        local plan = require("rfc.proposal").model(spec, "99", lines)
        local source = contract.from_model(plan)
        assert.is_not_nil(source.anchors["eip99-same"])
        assert.is_not_nil(source.anchors["eip99-same-2"])
        local plain = table.concat(source.markdown, "\n"):gsub("\\(%p)", "%1")
        local _, count = plain:gsub("%*/%*", "")
        assert.equals(2, count)
        assert.equals("Accept: `*/*`", plan.blocks[2].text)
    end)
end)
