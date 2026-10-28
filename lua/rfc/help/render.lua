-- Vim help projection of an RFC plan.
local formatting = require("rfc.help.text")
local with_tag = formatting.with_tag
local target = require("rfc.help.model").target
local version = require("rfc.help.version")
local M = {}

--- Replaces the first plain occurrence of `needle` in `line` with `repl`.
---@param line string
---@param needle string
---@param repl string
---@return string
local function replace_first(line, needle, repl)
    local first, last = line:find(needle, 1, true)
    if not first then
        return line
    end
    return line:sub(1, first - 1) .. repl .. line:sub(last + 1)
end

--- A block's text with every mention replaced by its link, last to first
--- so the earlier spans stay where the reader found them.
---@param b rfc.source.rfc.Block
---@param ctx rfc.help.Context
---@return string
local function link(b, ctx)
    local line = b.text
    for i = #b.mentions, 1, -1 do
        local m = b.mentions[i]
        local tag = target(m, ctx, b.citation)
        if tag then
            line = line:sub(1, m.first - 1) .. "|" .. tag .. "|" .. line:sub(m.last + 1)
        end
    end
    return line
end
---@param model rfc.RfcModel
---@return rfc.HelpDoc
function M.render_model(model)
    local blocks, tag_of, ctx, file_tag = model.blocks, model.tag_of, model.context, model.name
    local decorate = {
        header = function(b)
            return b.text
        end,
        heading = function(b)
            return with_tag(link(b, ctx), tag_of[b])
        end,
        row = function(b)
            local needle = b.section.label ~= "" and b.section.label or b.section.title
            return replace_first(link(b, ctx), needle, "|" .. tag_of[b] .. "|")
        end,
        reference = function(b)
            local text = link(b, ctx)
            return tag_of[b] and with_tag(text, tag_of[b]) or text
        end,
        line = function(b)
            return link(b, ctx)
        end,
    }

    local title = model.title
    local out = { with_tag("*" .. file_tag .. ".txt*  " .. title, file_tag) }
    local tags = { { name = file_tag, line = 1 }, { name = file_tag .. ".txt", line = 1 } }
    for _, b in ipairs(blocks) do
        table.insert(out, decorate[b.kind](b))
        if tag_of[b] and b.kind ~= "row" then
            table.insert(tags, { name = tag_of[b], line = #out })
        end
    end
    table.insert(out, "")
    table.insert(out, version.MODELINE)
    table.insert(out, version.FOOTER)
    return { lines = out, tags = tags, model = model }
end

return M
