-- Folds a report's body into blocks, the one list a renderer walks: headings
-- with their numbers and ids, paragraphs, code, tables, lists, definition
-- lists, figures, callouts (notes, examples, issues, details, tabbed
-- examples) and quotes, each text plain with its mentions. Loose inline
-- content between blocks gathers into paragraphs. `head` reads the title,
-- the subtitle, the metadata and the abstract.
local fp = require("cds.fp")
local tree = require("rfc.source.html.tree")
local inline = require("rfc.source.html.inline")
local tokens = require("rfc.source.html.tokens")

---@class rfc.source.html.blocks
local M = {}

local squash, plain = tokens.squash, tree.plain

---@class rfc.source.html.Block
---@field kind "heading"|"para"|"code"|"table"|"list"|"dl"|"figure"|"callout"|"quote"|"rule"
---@field line integer          -- the block's first line in the source
---@field level integer|nil     -- heading: 1 for h2 … 5 for h6
---@field number string|nil     -- heading: "5.3" when numbered
---@field id string|nil         -- heading, figure: the element's id
---@field section string|nil    -- heading: the enclosing section's id, which ReSpec's links target
---@field text rfc.source.html.Text|nil  -- heading, para
---@field lang string|nil       -- code
---@field code string[]|nil     -- code: the lines as written
---@field caption string|nil    -- table, figure
---@field header boolean|nil    -- table
---@field rows rfc.source.html.Text[][]|nil  -- table
---@field ordered boolean|nil   -- list
---@field items rfc.source.html.Block[][]|nil  -- list: each item's blocks
---@field entries { term: string, blocks: rfc.source.html.Block[] }[]|nil  -- dl
---@field alt string|nil        -- figure
---@field src string|nil        -- figure: the image URL as written
---@field label string|nil      -- callout
---@field blocks rfc.source.html.Block[]|nil  -- callout, quote

local elements = require("rfc.source.html.elements")
local tab_of = elements.tab
local blocks_of = require("rfc.source.html.walk")
local containers = require("rfc.source.html.containers")
local function entries_of(node, ctx, buttons)
    return containers.entries(node, ctx, buttons, blocks_of)
end

--- Collects the ids of every heading and section, and the labels of every
--- tabbed example's buttons.
---@param root rfc.source.html.Node
---@return table<string, boolean> ids
---@return table<string, string> buttons
local function survey(root)
    local ids = fp.set(
        tree.find_all(root, function(n)
            return n.attrs.id ~= nil and (n.name == "section" or n.name:match("^h[1-6]$") ~= nil)
        end),
        function(n)
            return n.attrs.id
        end
    )
    local buttons = {}
    for _, button in ipairs(tree.find_all(root, tree.named("button"))) do
        local tab, name = tab_of(button)
        if tab and name then
            buttons[tab .. "\0" .. name] = squash(plain(button))
        end
    end
    return ids, buttons
end

---@param root rfc.source.html.Node
---@return rfc.source.html.Context
---@return table<string, string> buttons
local function context(root)
    local ids, buttons = survey(root)
    return { ids = ids, abbr = {}, section = nil }, buttons
end

--- Folds the report's body into blocks: everything after the title, with the
--- contents and the head's furniture dropped, loose text gathered into
--- paragraphs, and every text plain with its mentions.
---@param lines string[]
---@return rfc.source.html.Block[]
function M.blocks(lines)
    local root = tree.of(lines)
    local ctx, buttons = context(root)
    return blocks_of(root.children, ctx, buttons)
end

--- Reads the report's head: the title, the subtitle line under it ("W3C
--- Recommendation 05 December 2023"), the metadata list and the abstract.
---@param lines string[]
---@return { title: string, subtitle: string, meta: { term: string, text: rfc.source.html.Text }[], abstract: rfc.source.html.Text[] }
function M.head(lines)
    local root = tree.of(lines)
    local ctx = context(root)
    local h1 = tree.by_id(root, "title") or tree.find_first(root, tree.named("h1"))
    local state = tree.by_id(root, "w3c-state") or tree.by_id(root, "subtitle")
    local dl = tree.find_first(root, tree.named("dl"))
    local meta = dl
            and fp.map(entries_of(dl, ctx, {}), function(e)
                local first = e.blocks[1]
                return { term = e.term, text = first and first.text or { text = "", mentions = {} } }
            end)
        or {}
    local abstract = {}
    local node, parent = tree.by_id(root, "abstract")
    if node then
        local holder = node.name:match("^h%d$") and parent or node
        abstract = fp.map(fp.filter(holder.children, tree.named("p")), function(p)
            return inline.inline(p.children, ctx)
        end)
    end
    return {
        title = h1 and squash(plain(h1)) or "",
        subtitle = state and squash(plain(state)) or "",
        meta = meta,
        abstract = abstract,
    }
end

return M
