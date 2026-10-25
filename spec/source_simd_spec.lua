local simd = require("rfc.source.simd")
local eip = require("rfc.source.eip")
local fixtures = require("spec.fixtures")

describe("mentions", function()
    it("reads a link to a proposal, the whole link, and the bare spellings", function()
        local line = "See [SIMD-0033](./0033-timely-vote-credits.md) and SIMD-0064, SIMD 88, SIMD-215."
        local found = simd.mentions(line)
        assert.are.same({ kind = "simd", id = "33", first = 5, last = 46 }, found[1])
        local ids = {}
        for _, m in ipairs(found) do
            table.insert(ids, m.id)
        end
        assert.are.same({ "33", "64", "88", "215" }, ids)
    end)
    it("reads a link by the repository's address, with a section", function()
        local line = "[x](https://github.com/solana-foundation/solana-improvement-documents"
            .. "/blob/main/proposals/0161-agave-v2.md#summary)"
        assert.are.same(
            { { kind = "simd", id = "161", section = "summary", first = 1, last = #line } },
            simd.mentions(line)
        )
    end)
    it("keeps the position of a bare mention after a link", function()
        local line = "See [SIMD-0033](./0033-timely-vote-credits.md) and SIMD-0064."
        local found = simd.mentions(line)
        assert.are.equal("SIMD-0064", line:sub(found[2].first, found[2].last))
    end)
    it("passes other links and other words", function()
        assert.are.same(
            {},
            simd.mentions("[spec](https://github.com/solana-labs/rbpf/blob/main/doc/bytecode.md) SIMDs SIMD-0064x")
        )
    end)
end)

describe("index", function()
    it("reads the proposals directory as the contents API lists it", function()
        local entries = simd.index(fixtures.read(fixtures.simd_listing))
        assert.are.equal(133, #entries)
        assert.are.same({ id = "1", file = "0001-simd-process.md", title = "Simd Process" }, entries[1])
        local e = fixtures.find(entries, "id", "64")
        assert.are.equal("0064-transaction-receipt.md", e.file)
        assert.are.equal("Transaction Receipt", e.title)
        assert.are.equal("Allow Commission Decrease At Any Time", fixtures.find(entries, "id", "79").title)
    end)
    it("reads nothing from another page", function()
        assert.are.same({}, simd.index({ "<html>", '"name": "README.md"', "</html>" }))
    end)
end)

describe("list", function()
    it("splits a frontmatter list the reader joined into one value", function()
        local fields = eip.frontmatter(fixtures.read(fixtures.simd64))
        assert.are.same(
            { "Anoushk Kharangate (Tinydancer)", "Richard Patel (Jump)", "Harsh Patel (Tinydancer)" },
            simd.list(fields.authors)
        )
    end)
    it("splits an inline value at its commas", function()
        assert.are.same(
            { "Haoran Yi (Anza)", "Justin Starry (Anza)" },
            simd.list("Haoran Yi (Anza), Justin Starry (Anza)")
        )
        assert.are.same({ "Justin Starry (Anza)" }, simd.list("Justin Starry (Anza)"))
    end)
    it("is empty for nothing", function()
        assert.are.same({}, simd.list(""))
        assert.are.same({}, simd.list(nil))
    end)
end)

describe("number", function()
    it("reads the number out of a quoted or bare value, without leading zeros", function()
        assert.are.equal("64", simd.number("'0064'"))
        assert.are.equal("506", simd.number('"0506"'))
        assert.are.equal("64", simd.number("64"))
        assert.is_nil(simd.number("TBD"))
    end)
end)
