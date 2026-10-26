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
end)
