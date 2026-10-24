-- The status axis, pure: the statuses a source's entries stand in, in the
-- source's lifecycle order, and the cycle a picker walks through them.
local status = require("rfc.status")
local fp = require("cds.fp")

describe("status.counts", function()
    local order = { "Draft", "Review", "Final" }

    it("lists the statuses present in lifecycle order, with counts", function()
        local entries = {
            { id = "1", status = "Final" },
            { id = "2", status = "Draft" },
            { id = "3", status = "Final" },
        }
        assert.are.same({ { name = "Draft", count = 1 }, { name = "Final", count = 2 } }, status.counts(order, entries))
    end)

    it("files a status outside the lifecycle after it, by name", function()
        local entries = {
            { id = "1", status = "Zombie" },
            { id = "2", status = "Final" },
            { id = "3", status = "Abandoned" },
        }
        local names = fp.map(status.counts(order, entries), function(c)
            return c.name
        end)
        assert.are.same({ "Final", "Abandoned", "Zombie" }, names)
    end)

    it("answers nothing for entries without a status", function()
        assert.are.same({}, status.counts(order, { { id = "1" } }))
    end)
end)

describe("status.named", function()
    it("spells a status as the lifecycle does, case aside, and leaves a stranger as written", function()
        assert.are.equal("Last Call", status.named({ "Draft", "Last Call" }, "last call"))
        assert.are.equal("Zombie", status.named({ "Draft" }, "Zombie"))
        assert.is_nil(status.named({ "Draft" }, nil))
    end)
end)

describe("status.chosen", function()
    before_each(function()
        status.chosen = {}
    end)

    it("takes the default before a choice, the choice after, and All as a choice of its own", function()
        assert.are.equal("Final", status.get("eip", "Final"))
        status.set("eip", "Draft")
        assert.are.equal("Draft", status.get("eip", "Final"))
        status.set("eip", nil)
        assert.is_nil(status.get("eip", "Final"))
    end)
end)

describe("status.next", function()
    local order = { "Draft", "Final" }

    it("walks none, each status in order, then none", function()
        assert.are.equal("Draft", status.next(order, nil))
        assert.are.equal("Final", status.next(order, "Draft"))
        assert.is_nil(status.next(order, "Final"))
    end)

    it("starts over from a status outside the order", function()
        assert.are.equal("Draft", status.next(order, "Zombie"))
    end)
end)
