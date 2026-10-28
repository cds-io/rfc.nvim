-- Local Markdown construction; source models remain immutable.
local html = require("cds.html")
local document = require("cds.document")
local M = {}
function M.new(model)
    local out, anchors, headings = { "# " .. html.escape(model.title) }, {}, {}
    anchors[model.name], anchors[model.name .. ".txt"] = 1, 1
    if model.kind == "proposal" then
        for _, alias in ipairs(model.aliases) do
            anchors[alias] = 1
        end
    end
    local function put(text)
        table.insert(out, text)
    end
    local function prose(text)
        local code = {}
        text = text:gsub("`[^`]*`", function(span)
            code[#code + 1] = span
            return "\3" .. #code .. "\4"
        end):gsub("%*", "\\*")
        return (text:gsub("\3(%d+)\4", function(index)
            return code[tonumber(index)]
        end))
    end
    local function linked(text, mentions, resolve)
        for i = #mentions, 1, -1 do
            local m = mentions[i]
            local target = resolve(m)
            if target then
                text = text:sub(1, m.first - 1) .. "\1" .. i .. "\2" .. text:sub(m.last + 1)
            end
        end
        text = prose(text)
        return (
            text:gsub("\1(%d+)\2", function(index)
                local target = resolve(mentions[tonumber(index)])
                return "[" .. target .. "](rfc-tag:" .. target .. ")"
            end)
        )
    end
    local function heading(tag, text, level, markdown)
        put(string.rep("#", math.min(level + 1, 6)) .. " " .. (markdown or html.escape(text)))
        anchors[tag] = #out
        table.insert(headings, { tag = tag, text = text, level = level, line = #out })
    end
    local function finish()
        local doc = document.new(out, { anchors = anchors }) --[[@as rfc.Document]]
        doc.headings = headings
        return doc
    end
    return {
        put = put,
        prose = prose,
        linked = linked,
        heading = heading,
        anchors = anchors,
        lines = out,
        finish = finish,
    }
end
return M
