local mentions = require("rfc.source.mentions")

local LINK = {
    "%[([%w%-]+)%]%(%./(%d+)%.md#?([%w%-]*)%)",
    function(_, id, section)
        return { kind = "x", id = id, section = section }
    end,
}
local BARE = {
    "X%-(%d+)",
    function(id)
        return { kind = "x", id = id }
    end,
}

describe("scan", function()
    it("finds links and bare spellings in order, each with its byte range", function()
        local line = "see X-1, [two](./2.md#part) and X-3"
        assert.are.same({
            { kind = "x", id = "1", first = 5, last = 7 },
            { kind = "x", id = "2", section = "part", first = 10, last = 27 },
            { kind = "x", id = "3", first = 33, last = 35 },
        }, mentions.scan(line, { LINK }, BARE))
    end)
    it("finds a link's text once and keeps the positions after it", function()
        local line = "[X-7](./7.md) then X-8"
        local found = mentions.scan(line, { LINK }, BARE)
        assert.are.equal(2, #found)
        assert.are.equal("X-8", line:sub(found[2].first, found[2].last))
    end)
    it("takes a bare spelling only on its own", function()
        assert.are.same({}, mentions.scan("aX-1 X-2b -X-3", { LINK }, BARE))
        assert.are.equal(2, #mentions.scan("(X-5) X-6.", { LINK }, BARE))
    end)
    it("leaves out a match the form answers nil for", function()
        local none = {
            "X%-(%d+)",
            function()
                return nil
            end,
        }
        assert.are.same({}, mentions.scan("X-1", {}, none))
    end)
    it("finds nothing in an empty line", function()
        assert.are.same({}, mentions.scan("", { LINK }, BARE))
    end)
end)
