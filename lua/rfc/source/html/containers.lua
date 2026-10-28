-- Figures and definition lists, with the recursive fold supplied explicitly.
local fp = require("cds.fp")
local tree = require("rfc.source.html.tree")
local tokens = require("rfc.source.html.tokens")
local squash, plain = tokens.squash, tree.plain
local label_of = require("rfc.source.html.elements").label
local M = {}

--- Reads an object's fallback content as one line of text: the list a Bikeshed
--- object carries, each item numbered or dashed.
---@param blocks rfc.source.html.Block[]
---@return string
local function fallback_text(blocks)
    return squash(table.concat(
        fp.map(blocks, function(blk)
            if blk.kind == "list" then
                return table.concat(
                    fp.map(blk.items, function(item, i)
                        local first = item[1]
                        return (blk.ordered and (i .. ". ") or "- ") .. (first and first.text and first.text.text or "")
                    end),
                    " "
                )
            end
            return blk.text and blk.text.text or ""
        end),
        " "
    ))
end
--- Builds a figure block from a `figure`, a bare `img`, or an `object`; nil for
--- an image with nothing to say.
---@param child rfc.source.html.Node
---@param ctx rfc.source.html.Context
---@param buttons table<string, string>
---@return rfc.source.html.Block|nil
function M.figure(child, ctx, buttons, blocks_of)
    local img, caption = child, nil ---@type rfc.source.html.Node?, string?
    if child.name == "figure" then
        img = fp.find(child.children, function(c)
            return type(c) ~= "string" and (c.name == "img" or c.name == "object")
        end) --[[@as rfc.source.html.Node?]]
        local fc = fp.find(child.children, tree.named("figcaption")) --[[@as rfc.source.html.Node?]]
        caption = fc and label_of(fc) or nil
    end
    if not img then
        return nil
    end
    local alt = img.attrs.alt
    if img.name == "object" and (not alt or alt == "") then
        alt = fallback_text(blocks_of(img.children, ctx, buttons))
    end
    if child.name ~= "figure" and (not alt or alt == "") then
        return nil
    end
    return {
        kind = "figure",
        line = child.line,
        id = child.attrs.id,
        caption = caption,
        alt = alt or "",
        src = img.attrs.src or img.attrs.data or "",
    }
end

--- Reads a definition list's entries: each `dt` is a term and the `dd`s after
--- it are its blocks; a `dd` before any `dt` gets an empty term.
---@param node rfc.source.html.Node
---@param ctx rfc.source.html.Context
---@param buttons table<string, string>
---@return { term: string, blocks: rfc.source.html.Block[] }[]
function M.entries(node, ctx, buttons, blocks_of)
    local entries = {}
    for _, c in ipairs(node.children) do
        if type(c) ~= "string" and c.name == "dt" then
            table.insert(entries, { term = squash(plain(c)), blocks = {} })
        elseif type(c) ~= "string" and c.name == "dd" then
            if #entries == 0 then
                table.insert(entries, { term = "", blocks = {} })
            end
            for _, blk in ipairs(blocks_of(c.children, ctx, buttons)) do
                table.insert(entries[#entries].blocks, blk)
            end
        end
    end
    return entries
end

return M
