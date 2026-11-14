-- The registry: a spec registers for nothing, its record loads on first use
-- with the identity merged in, tags resolve by prefix and alias, and a taken
-- prefix stays its first module's.
local tags = require("rfc.help.tags")

local MODULES = { "rfc.sources", "spec.fake.alpha", "spec.fake.beta" }
local saved, loads, sources

local function spec(over)
    local s = { prefix = "alp", label = "ALP", command = "Alp", desc = "Open an ALP", module = "spec.fake.alpha" }
    for k, v in pairs(over or {}) do
        s[k] = v
    end
    return s
end

before_each(function()
    saved = { loaded = {}, preload = {} }
    for _, name in ipairs(MODULES) do
        saved.loaded[name], saved.preload[name] = package.loaded[name], package.preload[name]
        package.loaded[name] = nil
    end
    loads = {}
    for _, name in ipairs({ "spec.fake.alpha", "spec.fake.beta" }) do
        package.preload[name] = function()
            loads[name] = (loads[name] or 0) + 1
            return { raw_ext = "txt", from = name }
        end
    end
    sources = require("rfc.sources")
end)

after_each(function()
    for _, name in ipairs(MODULES) do
        package.loaded[name], package.preload[name] = saved.loaded[name], saved.preload[name]
    end
    tags.set_shortnames({})
end)

describe("register", function()
    it("costs nothing: the record loads on first use, with the spec's identity merged in", function()
        assert.is_true(sources.register(spec({ aliases = { "alq" }, default_on = true })))
        assert.is_nil(loads["spec.fake.alpha"])
        local record = sources.get("alp")
        assert.are.equal(1, loads["spec.fake.alpha"])
        assert.are.same(
            { "alp", "ALP", "Alp", { "alq" }, true, "txt" },
            { record.prefix, record.label, record.command, record.aliases, record.default_on, record.raw_ext }
        )
        assert.are.equal(record, sources.get("alp"))
        assert.are.equal(1, loads["spec.fake.alpha"])
    end)

    it("keeps a taken prefix its first module's, and takes the same spec again", function()
        assert.is_true(sources.register(spec()))
        local ok, err = sources.register(spec({ module = "spec.fake.beta" }))
        assert.is_nil(ok)
        assert.are.equal("source alp is spec.fake.alpha already; spec.fake.beta cannot take it", err)
        assert.is_true(sources.register(spec({ label = "Alpha" })))
        assert.are.equal(1, #sources.specs())
        assert.are.equal("Alpha", sources.get("alp").label)
    end)

    it("answers why a spec without a module cannot register", function()
        local s = spec()
        s.module = nil
        assert.are.same({ nil, "a source spec needs module, a string" }, { sources.register(s) })
        assert.are.same({}, sources.specs())
    end)

    it("names the shortname sources to the tag shapes", function()
        sources.register(spec({ prefix = "bet", key = "shortname", module = "spec.fake.beta" }))
        sources.register(spec())
        assert.are.same({ "bet" }, sources.shortnames())
        assert.are.equal("bet-some-report#intro", tags.section_tag("Intro  *bet-some-report#intro*"))
    end)
end)

describe("of", function()
    it("finds a tag's source by prefix or alias, number or shortname, loading that one alone", function()
        sources.register(spec({ aliases = { "alq" } }))
        sources.register(spec({ prefix = "bet", key = "shortname", module = "spec.fake.beta" }))
        assert.are.equal("spec.fake.alpha", sources.of("alp12-abstract").from)
        assert.are.equal("spec.fake.alpha", sources.of("alq7").from)
        assert.is_nil(loads["spec.fake.beta"])
        assert.are.equal("spec.fake.beta", sources.of("bet-some-report#intro").from)
        assert.are.equal("spec.fake.alpha", sources.of("alp-subjects").from)
        assert.is_nil(sources.of("zzz9"))
        assert.is_nil(sources.of("not a tag"))
    end)
end)

describe("all", function()
    it("answers every source in registration order", function()
        sources.register(spec({ prefix = "bet", module = "spec.fake.beta" }))
        sources.register(spec())
        local all = sources.all()
        assert.are.same({ "spec.fake.beta", "spec.fake.alpha" }, { all[1].from, all[2].from })
    end)
end)
