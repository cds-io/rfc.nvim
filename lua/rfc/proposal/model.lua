-- Prepare a proposal once for help and Markdown.
local fp = require("cds.fp")
local inline = require("rfc.proposal.inline")
local row_parts, label = inline.row_parts, inline.label
local body = require("rfc.proposal.plan")
local M = {}

--- The document for a proposal's text, total: an empty text gives the
--- title line, the header and the footer.
---@param spec rfc.ProposalSpec
---@param id string
---@param lines string[]
---@return rfc.ProposalModel
function M.model(spec, id, lines)
    local fields, blocks = spec.read(lines)
    local name = spec.prefix .. id
    local header = fp.map(
        fp.filter(spec.header, function(key)
            return fields[key] ~= nil and fields[key] ~= ""
        end),
        function(key)
            return label(key) .. ": " .. fields[key]
        end
    )
    table.insert(header, 1, spec.number(fields, id))
    local rows = { { { text = table.concat(header, "  ") } } }
    for _, row in ipairs(spec.rows) do
        local line = type(row) == "function" and row(fields, id)
            or type(row) == "table" and row_parts(spec.prefix, fields, row)
        if line then
            table.insert(rows, type(line) == "string" and { { text = line } } or line)
        end
    end
    local inlines = { [""] = {} }
    local function prepare(text)
        if text and not inlines[text] then
            inlines[text] = inline.inline(spec, id, text)
        end
    end
    for _, block in ipairs(blocks) do
        prepare(block.text)
        for _, cells in ipairs(block.rows or {}) do
            for _, cell in ipairs(cells) do
                prepare(cell)
            end
        end
        for _, note in ipairs(block.notes or {}) do
            prepare(note.text)
        end
    end
    return {
        kind = "proposal",
        name = name,
        id = id,
        blocks = blocks,
        title = fields.title or (spec.label(fields) .. " " .. id),
        fields = fields,
        aliases = spec.tags and spec.tags(fields, id) or {},
        header = rows,
        inlines = inlines,
        body = body.plan_body(blocks, name),
    }
end

return M
