-- Help body layout and shared heading identities.
local help = require("rfc.help")
local fp = require("cds.fp")
local M = {}
M.plan_body = require("rfc.proposal.plan").plan_body

--- A table as aligned columns: its caption on a line of its own, cells
--- padded to their column, two spaces apart, indented by two, and a rule
--- of dashes under a heading row. No bar survives, since help would read
--- |cell| as a link.
---@param t { caption: string|nil, header: boolean, rows: string[][] }
---@return string[]
function M.layout(t)
    local widths = {}
    for _, row in ipairs(t.rows) do
        for c, cell in ipairs(row) do
            widths[c] = math.max(widths[c] or 0, #cell)
        end
    end
    local function line(cells)
        local padded = fp.map(widths, function(width, c)
            local cell = cells[c] or ""
            return cell .. string.rep(" ", width - #cell)
        end)
        return ("  " .. table.concat(padded, "  ")):gsub("%s+$", "")
    end
    local out = fp.map(t.rows, function(row)
        return (line(row))
    end)
    if t.header and #out > 0 then
        local rule = fp.map(widths, function(width)
            return string.rep("-", width)
        end)
        table.insert(out, 2, (line(rule)))
    end
    if t.caption then
        table.insert(out, 1, "  " .. t.caption)
    end
    return out
end

--- The body: a CONTENTS block of the headings as links, indented by level
--- from the shallowest heading, then every block rendered. Level one and
--- two headings are written in capitals. Answers the lines and the tags
--- they carry, each tag's line counted from 1 within the lines answered.
---@param blocks rfc.ProposalBlock[]
---@param file_tag string
---@param link fun(text: string): string   -- the render's link pass over a line
---@param plan? rfc.ProposalPlan
---@return string[] lines
---@return rfc.HelpTag[] tags
function M.body(blocks, file_tag, link, plan)
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local prepared = plan or M.plan_body(blocks, file_tag)
    local tag_of, top = prepared.tags, prepared.top
    if next(tag_of) then
        put("CONTENTS")
        for _, b in ipairs(blocks) do
            if b.kind == "heading" then
                put(string.rep("  ", b.level - top + 1) .. "|" .. tag_of[b] .. "|  " .. b.title)
            end
        end
        put("")
    end

    local render = {
        heading = function(b)
            return { help.with_tag(prepared.texts[b], tag_of[b]) }
        end,
        fence = function(b)
            local block = fp.map(b.code, function(code)
                return "    " .. code
            end)
            table.insert(block, 1, ">" .. b.lang)
            table.insert(block, "<")
            return block
        end,
        table = M.layout,
        notes = function(b)
            return fp.map(b.notes, function(note)
                return "[" .. note.n .. "] " .. link(note.text)
            end)
        end,
        line = function(b)
            local text = link(b.text)
            -- a leading < would read as the end of a code block and vanish
            return { text:match("^<") and (" " .. text) or text }
        end,
    }
    for _, b in ipairs(blocks) do
        for _, line in ipairs(render[b.kind](b)) do
            put(line)
        end
        if b.kind == "heading" then
            table.insert(tags, { name = tag_of[b], line = #out })
        end
    end
    return out, tags
end

return M
