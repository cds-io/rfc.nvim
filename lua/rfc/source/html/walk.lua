-- Fold HTML children into source blocks.
local fp = require("cds.fp")
local tree = require("rfc.source.html.tree")
local inline = require("rfc.source.html.inline")
local tokens = require("rfc.source.html.tokens")
local squash, plain, classes = tokens.squash, tree.plain, tree.classes
local elements = require("rfc.source.html.elements")
local secno, tab_of, code_lang, code_lines = elements.secno, elements.tab, elements.code_lang, elements.code_lines
local table_of, label_of = elements.table, elements.label
local containers = require("rfc.source.html.containers")

--- The blocks under a node's children, with loose inline content between
--- blocks gathered into paragraphs.
---@param children (rfc.source.html.Node|string)[]
---@param ctx rfc.source.html.Context
---@param buttons table<string, string>   -- tab .. name -> the button's label
---@return rfc.source.html.Block[]
local function blocks_of(children, ctx, buttons)
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
            put({ kind = "dl", line = child.line, entries = containers.entries(child, ctx, buttons, blocks_of) })
        elseif child.name == "figure" or child.name == "img" or child.name == "object" then
            flush()
            local figure = containers.figure(child, ctx, buttons, blocks_of)
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
            -- GitHub's alert: a quote opening with a paragraph of `[!KIND]`,
            -- a title after it on the line or none, is a callout labelled by
            -- the title, else the kind
            local first, rest = tree.split(child.children, tree.named("p"))
            local kind, title = (first and squash(plain(first)) or ""):match("^%[!(%a+)%]%s*(.*)$")
            if kind then
                local label = title ~= "" and title or (kind:sub(1, 1):upper() .. kind:sub(2):lower())
                callout(label, child.line, rest)
            else
                put({ kind = "quote", line = child.line, blocks = blocks_of(child.children, ctx, buttons) })
            end
        elseif child.name == "hr" then
            flush()
            put({ kind = "rule", line = child.line })
        elseif child.name == "section" then
            flush()
            local nested = { ids = ctx.ids, abbr = ctx.abbr, section = child.attrs.id or ctx.section }
            for _, blk in ipairs(blocks_of(child.children, nested, buttons)) do
                put(blk)
            end
        else
            -- an element the rules do not name is transparent
            flush()
            descend(child)
        end
    end
    flush()
    return out
end

return blocks_of
