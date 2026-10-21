-- What every proposal render shares once its header is written: the body
-- as one fold over the reader's blocks, with a contents block of links
-- first. A heading gets a tag of the file tag and its slug (numbered when
-- a title repeats), a fence becomes a help code block, a table aligned
-- columns, the notes a numbered list, and a line goes through the render's
-- own link pass. Nothing here touches the editor.
local help = require("rfc.help")

local M = {}

--- A table as aligned columns: cells padded to their column, two spaces
--- apart, indented by two, and a rule of dashes under a heading row. No bar
--- survives, since help would read |cell| as a link.
---@param t { header: boolean, rows: string[][] }
---@return string[]
function M.layout(t)
    local widths = {}
    for _, row in ipairs(t.rows) do
        for c, cell in ipairs(row) do
            widths[c] = math.max(widths[c] or 0, #cell)
        end
    end
    local function line(cells)
        local padded = {}
        for c, width in ipairs(widths) do
            local cell = cells[c] or ""
            padded[c] = cell .. string.rep(" ", width - #cell)
        end
        return ("  " .. table.concat(padded, "  ")):gsub("%s+$", "")
    end
    local out = {}
    for r, row in ipairs(t.rows) do
        table.insert(out, (line(row)))
        if r == 1 and t.header then
            local rule = {}
            for c, width in ipairs(widths) do
                rule[c] = string.rep("-", width)
            end
            table.insert(out, (line(rule)))
        end
    end
    return out
end

---@class rfc.ProposalBlock
---@field kind "heading"|"fence"|"table"|"notes"|"line"
---@field level integer|nil
---@field title string|nil
---@field lang string|nil
---@field code string[]|nil
---@field header boolean|nil
---@field rows string[][]|nil
---@field notes { n: integer, text: string }[]|nil
---@field text string|nil

--- The body: a CONTENTS block of the headings as links, indented by level,
--- then every block rendered. Level one and two headings are written in
--- capitals. Answers the lines and the tags they carry, each tag's line
--- counted from 1 within the lines answered.
---@param blocks rfc.ProposalBlock[]
---@param file_tag string
---@param link fun(text: string): string   -- the render's link pass over a line
---@return string[] lines
---@return rfc.HelpTag[] tags
function M.body(blocks, file_tag, link)
    local out, tags = {}, {}
    local function put(line)
        table.insert(out, line)
    end
    local tag_of, used = {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "heading" then
            local name = file_tag .. "-" .. help.slug(b.title)
            if used[name] then
                used[name] = used[name] + 1
                name = name .. "-" .. used[name]
            else
                used[name] = 1
            end
            tag_of[b] = name
        end
    end
    if next(tag_of) then
        put("CONTENTS")
        for _, b in ipairs(blocks) do
            if b.kind == "heading" then
                put(string.rep("  ", math.max(b.level - 1, 1)) .. "|" .. tag_of[b] .. "|  " .. b.title)
            end
        end
        put("")
    end

    local render = {
        heading = function(b)
            return { help.with_tag(b.level <= 2 and b.title:upper() or b.title, tag_of[b]) }
        end,
        fence = function(b)
            local block = { ">" .. b.lang }
            for _, code in ipairs(b.code) do
                table.insert(block, "    " .. code)
            end
            table.insert(block, "<")
            return block
        end,
        table = M.layout,
        notes = function(b)
            local block = {}
            for _, note in ipairs(b.notes) do
                table.insert(block, "[" .. note.n .. "] " .. link(note.text))
            end
            return block
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
