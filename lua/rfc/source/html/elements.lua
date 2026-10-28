-- Heading, code, table and label readers.
local fp = require("cds.fp")
local tree = require("rfc.source.html.tree")
local inline = require("rfc.source.html.inline")
local tokens = require("rfc.source.html.tokens")
local squash, plain, classes = tokens.squash, tree.plain, tree.classes

local M = {}

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

M.label, M.secno, M.code_lines, M.code_lang, M.tab, M.table = label_of, secno, code_lines, code_lang, tab_of, table_of

return M
