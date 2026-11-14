-- rfc.headings: a buffer's outline in any view, from the document model when
-- the reader has one and from the help text otherwise, parsed once per text.
local headings = require("rfc.headings")

describe("a buffer's headings", function()
    local buf
    before_each(function()
        buf = vim.api.nvim_create_buf(false, true)
        local fixtures = require("spec.fixtures")
        local lines = require("rfc.sources.rfc.render").render("9110", fixtures.read(fixtures.rfc9110)).lines
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end)
    after_each(function()
        headings.configure(function()
            return nil
        end)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("reads a help buffer's text once per change", function()
        local first = headings.headings(buf)
        assert.is_true(#first > 0)
        assert.are.equal(first, headings.headings(buf))
        vim.api.nvim_buf_set_lines(buf, 0, 1, false, {})
        assert.are_not.equal(first, headings.headings(buf))
    end)

    it("takes a document page's headings from the reader first", function()
        local from_model = { { line = 9, level = 1, text = "From the model" } }
        headings.configure(function(b)
            return b == buf and from_model or nil
        end)
        assert.are.equal(from_model, headings.headings(buf))
    end)
end)

describe("the contents sidebar's highlight", function()
    it("is defined without the rich view loaded", function()
        package.loaded["rfc.view"] = nil
        require("rfc.toc")
        assert.is_nil(package.loaded["rfc.view"])
        assert.are.equal("Title", vim.api.nvim_get_hl(0, { name = "rfcHeading" }).link)
    end)
end)
