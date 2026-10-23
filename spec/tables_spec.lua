local tables = require("rfc.tables")

describe("tables.of", function()
    it("reads an aligned table back from its caption line to the blank, cells by column", function()
        local lines =
            { "x", "Table 1: Names ~", "  Name  Description", "  ----  -----------", "  id    x y", "", "next" }
        assert.are.same({
            { caption_line = 2, first = 3, last = 5, header = { "Name", "Description" }, rows = { { "id", "x y" } } },
        }, tables.of(lines))
    end)
    it("reads a table without a header; a cell's inner spaces survive when another row fills the gap", function()
        local lines = { "Table ~", "  a    b  c", "  dd   efghi", "" }
        assert.are.same({
            { caption_line = 1, first = 2, last = 3, header = nil, rows = { { "a", "b  c" }, { "dd", "efghi" } } },
        }, tables.of(lines))
    end)
    it("finds nothing without a caption", function()
        assert.are.same({}, tables.of({ "  A  B", "" }))
    end)
end)

describe("tables.entries", function()
    it("writes each row as its first cell over the other cells as labelled lines, wrapped", function()
        local t = {
            header = { "Name", "Description", "Type" },
            rows = { { "id", "an identifier that is long enough to wrap at the width", "string" } },
        }
        assert.are.same({
            "id",
            "    Description: an identifier that is",
            "    long enough to wrap at the width",
            "    Type: string",
        }, tables.entries(t, 40))
    end)
    it("labels the cells by column number without a header", function()
        assert.are.same({ "a", "    2: b" }, tables.entries({ rows = { { "a", "b" } } }, 40))
    end)
end)
