-- The fact line: what a report's JSON record said, carried into the stored
-- HTML as one comment on its first line, so the render stays pure over the
-- lines and a re-render after a renderer upgrade still has the version
-- count, the first date, the topics and the links back to the original. The
-- tokenizer skips a comment, so the readers never see it; the model builder
-- reads it back.
---@class rfc.source.crs.facts
local M = {}

local KEYS = { "pdf", "mirror", "source" }

--- The facts as one HTML comment: id, versions, first, topics (joined with
--- semicolons), then each link that is known.
---@param v rfc.source.crs.Version
---@return string
function M.facts(v)
    local parts = {
        "id=" .. v.number,
        "versions=" .. v.count,
        "first=" .. v.first,
        "topics=" .. table.concat(v.topics or {}, ";"),
    }
    for _, key in ipairs(KEYS) do
        if v[key] then
            table.insert(parts, key .. "=" .. v[key])
        end
    end
    return "<!-- crs: " .. table.concat(parts, " ") .. " -->"
end

local FACT_KEYS = { id = true, versions = true, first = true, topics = true, pdf = true, mirror = true, source = true }

--- The facts a fact line carries, or nil for any other line. A value runs
--- to the next known ` key=`, so a topic name may hold spaces and a link
--- its own `?prodcode=` without either being read as a key.
---@param line string
---@return { id: string, versions: integer, first: string, topics: string[], pdf: string|nil, mirror: string|nil, source: string|nil }|nil
function M.read_facts(line)
    local inner = line:match("^<!%-%- crs: (.-) %-%->$")
    if not inner then
        return nil
    end
    local facts, starts = {}, {}
    for pos, key in (" " .. inner):gmatch("() (%w+)=") do
        if FACT_KEYS[key] then
            table.insert(starts, { pos = pos, key = key })
        end
    end
    for i, s in ipairs(starts) do
        local from = s.pos + #s.key + 2
        local to = starts[i + 1] and starts[i + 1].pos - 1 or #inner + 1
        facts[s.key] = (" " .. inner):sub(from, to)
    end
    local topics = {}
    for name in (facts.topics or ""):gmatch("[^;]+") do
        table.insert(topics, name)
    end
    return {
        id = facts.id or "",
        versions = tonumber(facts.versions) or 0,
        first = facts.first or "",
        topics = topics,
        pdf = facts.pdf,
        mirror = facts.mirror,
        source = facts.source,
    }
end

return M
