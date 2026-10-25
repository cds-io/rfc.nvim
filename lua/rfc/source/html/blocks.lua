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

local squash, plain, classes = tokens.squash, tree.plain, tree.classes

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

local is_self_link = tree.classed("self-link")

--- Builds a label from a self-link part ("Figure 1", "Example 1") and the rest
--- ("Smart Home", ": Sample"): "Figure 1: Smart Home".
---@param node rfc.source.html.Node
---@return string
local function label_of(node)
    local link = fp.filter(node.children, is_self_link)
    local rest = fp.filter(node.children, function(c)
        return not is_self_link(c)
    end)
    local a = squash(table.concat(fp.map(link, plain), " "))
    local b = squash(table.concat(fp.map(rest, plain), " "))
    if a == "" then
        return b
    elseif b == "" then
        return a
    elseif b:sub(1, 1) == ":" then
        return a .. ": " .. squash(b:sub(2))
    end
    return a .. ": " .. b
end

--- Reads the heading number a `.secno` child holds, without its trailing dot,
--- and answers the heading's children without it and without the empty self-
--- link a heading carries.
---@param node rfc.source.html.Node
---@return string|nil number
---@return (rfc.source.html.Node|string)[] rest
local function secno(node)
    local found, rest = tree.split(node.children, tree.classed("secno"))
    local number = found and squash(plain(found)):gsub("%.$", "") or nil
    return number ~= "" and number or nil, fp.filter(rest, function(c)
        return not is_self_link(c)
    end)
end

--- Reads the code lines of a `pre`: every string under it, as written, with the
--- one newline a browser drops after the opening tag dropped too.
---@param node rfc.source.html.Node
---@return string[]
local function code_lines(node)
    local raw = plain(node):gsub("^\n", "")
    local lines = {}
    for line in (raw .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

---@param node rfc.source.html.Node
---@return string
local function code_lang(node)
    local lang = (node.attrs.class or ""):match("lang%-(%w+)")
    if lang then
        return lang
    end
    local code = fp.find(node.children, tree.named("code"))
    return code and ((code.attrs.class or ""):match("hljs%s+(%w+)") or "") or ""
end

--- Reads the tab and the name a tabbed-example class list carries, or nil.
---@param node rfc.source.html.Node
---@return string|nil tab
---@return string|nil name
local function tab_of(node)
    local tab, name
    for c in pairs(classes(node)) do
        if c:match("^exampleTab%d+$") then
            tab = c
        elseif c ~= "selected" then
            name = c
        end
    end
    return tab, name
end

--- Reads a table's rows as texts; a cell's blocks are joined with spaces.
---@param node rfc.source.html.Node
---@param ctx rfc.source.html.Context
---@return string|nil caption
---@return boolean header
---@return rfc.source.html.Text[][] rows
local function table_of(node, ctx)
    local caption, header, rows = nil, false, {}
    local is_cell = function(c)
        return type(c) ~= "string" and (c.name == "td" or c.name == "th")
    end
    local function walk(n)
        for _, child in ipairs(n.children) do
            if type(child) ~= "string" then
                if child.name == "caption" then
                    caption = label_of(child)
                elseif child.name == "tr" then
                    local cells = fp.filter(child.children, is_cell)
                    if #rows == 0 and #cells > 0 and fp.all(cells, tree.named("th")) then
                        header = true
                    end
                    table.insert(
                        rows,
                        fp.map(cells, function(c)
                            -- a cell is one line: a hard break is a space, the same
                            -- width, so the mentions' ranges hold
                            local text = inline.inline(c.children, ctx)
                            text.text = text.text:gsub("\n", " ")
                            return text
                        end)
                    )
                elseif child.name == "thead" or child.name == "tbody" or child.name == "tfoot" then
                    walk(child)
                end
            end
        end
    end
    walk(node)
    return caption, header, rows
end

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

local blocks_of

--- Builds a figure block from a `figure`, a bare `img`, or an `object`; nil for
--- an image with nothing to say.
---@param child rfc.source.html.Node
---@param ctx rfc.source.html.Context
---@param buttons table<string, string>
---@return rfc.source.html.Block|nil
local function figure_of(child, ctx, buttons)
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
local function entries_of(node, ctx, buttons)
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

--- The blocks under a node's children, with loose inline content between
--- blocks gathered into paragraphs.
---@param children (rfc.source.html.Node|string)[]
---@param ctx rfc.source.html.Context
---@param buttons table<string, string>   -- tab .. name -> the button's label
---@return rfc.source.html.Block[]
blocks_of = function(children, ctx, buttons)
    local out, loose, loose_line = {}, {}, nil
    local function put(block)
        table.insert(out, block)
    end
    local function flush()
        if #loose > 0 then
            local text = inline.inline(loose, ctx)
            if text.text ~= "" then
                put({ kind = "para", line = loose_line, text = text })
            end
            loose = {}
        end
    end
    local function gather(child)
        if #loose == 0 then
            loose_line = type(child) == "string" and nil or child.line
        end
        table.insert(loose, child)
    end
    local function callout(label, line, body)
        put({ kind = "callout", line = line, label = label, blocks = blocks_of(body, ctx, buttons) })
    end
    local function descend(node)
        for _, blk in ipairs(blocks_of(node.children, ctx, buttons)) do
            put(blk)
        end
    end
    for _, child in ipairs(children) do
        if type(child) == "string" or (inline.INLINE[child.name] and child.name ~= "img") then
            gather(child)
        elseif inline.dropped(child) or child.name == "h1" then
            -- dropped with its contents; the title is the head's
            flush()
        elseif child.name:match("^h[2-6]$") then
            flush()
            local number, rest = secno(child)
            put({
                kind = "heading",
                line = child.line,
                level = tonumber(child.name:sub(2)) - 1,
                number = number,
                id = child.attrs.id or ctx.section,
                section = ctx.section,
                text = inline.inline(rest, ctx),
            })
        elseif child.name == "p" and classes(child).note then
            flush()
            local marker, rest = tree.split(child.children, tree.classed("marker"))
            local label = marker and squash(plain(marker)):gsub(":$", "") or "Note"
            callout(label, child.line, { { name = "p", attrs = {}, children = rest, line = child.line } })
        elseif child.name == "p" then
            flush()
            local text = inline.inline(child.children, ctx)
            if text.text ~= "" then
                put({ kind = "para", line = child.line, text = text })
            end
        elseif child.name == "pre" then
            flush()
            local tab, name = tab_of(child)
            local block = { kind = "code", line = child.line, lang = code_lang(child), code = code_lines(child) }
            if tab and name then
                put({
                    kind = "callout",
                    line = child.line,
                    label = buttons[tab .. "\0" .. name] or name,
                    blocks = { block },
                })
            else
                put(block)
            end
        elseif child.name == "table" then
            flush()
            local caption, header, rows = table_of(child, ctx)
            put({ kind = "table", line = child.line, caption = caption, header = header, rows = rows })
        elseif child.name == "ul" or child.name == "ol" then
            flush()
            local items = fp.map(fp.filter(child.children, tree.named("li")), function(li)
                return blocks_of(li.children, ctx, buttons)
            end)
            put({ kind = "list", line = child.line, ordered = child.name == "ol", items = items })
        elseif child.name == "dl" then
            flush()
            put({ kind = "dl", line = child.line, entries = entries_of(child, ctx, buttons) })
        elseif child.name == "figure" or child.name == "img" or child.name == "object" then
            flush()
            local figure = figure_of(child, ctx, buttons)
            if figure then
                put(figure)
            end
        elseif (child.name == "aside" or child.name == "div") and classes(child).example then
            flush()
            local marker, rest = tree.split(child.children, tree.classed("marker"))
            callout(marker and label_of(marker) or "Example", child.line, rest)
        elseif child.name == "div" and classes(child).note then
            flush()
            local title, rest = tree.split(child.children, tree.classed("note-title"))
            callout(title and squash(plain(title)) or "Note", child.line, rest)
        elseif child.name == "div" and classes(child).issue then
            flush()
            callout("Issue", child.line, child.children)
        elseif child.name == "details" then
            flush()
            local summary, rest = tree.split(child.children, tree.named("summary"))
            callout(summary and squash(inline.inline(summary.children, ctx).text) or "Details", child.line, rest)
        elseif child.name == "blockquote" then
            flush()
            put({ kind = "quote", line = child.line, blocks = blocks_of(child.children, ctx, buttons) })
        elseif child.name == "hr" then
            flush()
            put({ kind = "rule", line = child.line })
        elseif child.name == "section" then
            flush()
            local saved = ctx.section
            ctx.section = child.attrs.id or ctx.section
            descend(child)
            ctx.section = saved
        else
            -- an element the rules do not name is transparent
            flush()
            descend(child)
        end
    end
    flush()
    return out
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
