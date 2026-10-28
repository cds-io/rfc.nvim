-- Reads a node's inline text. Pieces are appended with whitespace folded at
-- the seams, code is wrapped in backticks, an abbreviation is expanded once,
-- and every link becomes a mention with its byte range: a section of the
-- report, another report, or a reference entry. Everything else is the text
-- alone.
local fp = require("cds.fp")
local tree = require("rfc.source.html.tree")
local tokens = require("rfc.source.html.tokens")

---@class rfc.source.html.inline
local M = {}

local squash = tokens.squash

-- Elements dropped with their contents: generator machinery, controls and
-- text meant for screen readers.
-- stylua: ignore
local DROPPED = fp.set({
  "head", "dialog", "button", "input", "form", "select", "textarea", "noscript", "template", "svg",
  "iframe", "video", "audio", "canvas",
})

-- Inline elements: these gather into loose text between blocks; any other
-- element the rules do not name is transparent, its blocks read through.
-- stylua: ignore
M.INLINE = fp.set({
  "a", "abbr", "b", "i", "em", "strong", "code", "var", "samp", "kbd", "tt", "span", "bdi", "bdo", "sup", "sub",
  "small", "mark", "u", "s", "del", "ins", "q", "cite", "dfn", "time", "br", "wbr", "label", "data", "img",
})

-- Inline elements whose text is wrapped in backticks.
local CODE = fp.set({ "code", "var", "samp", "kbd", "tt" })

--- Whether a node is dropped with its contents.
---@param node rfc.source.html.Node
---@return boolean
function M.dropped(node)
    if DROPPED[node.name] or (node.name == "nav" and node.attrs.id == "toc") then
        return true
    end
    local c = tree.classes(node)
    return (
        c.screenreader
        or c.caret
        or c["dfn-panel"]
        or (node.name == "ol" and c.toc)
        or (node.name == "div" and c.head)
    ) == true
end

---@class rfc.source.html.Context
---@field ids table<string, boolean>    -- the ids of headings and sections
---@field abbr table<string, boolean>   -- the abbreviations already expanded
---@field section string|nil            -- the enclosing section's id

---@class rfc.source.html.Text
---@field text string
---@field mentions rfc.source.Mention[]

local builder = require("rfc.source.html.builder")

local inline_into

--- Reads the shortname of a fragment-free report URL, or nil.
---@param href string
---@return string|nil
local function report_of(href)
    return href:match("^https?://www%.w3%.org/TR/([^/#?]+)/?$")
end

--- Appends an anchor to the builder as text, a mention, or text with its URL
--- once.
---@param node rfc.source.html.Node
---@param b table
---@param ctx rfc.source.html.Context
local function anchor(node, b, ctx)
    local href = node.attrs.href or ""
    local inner = builder()
    inline_into(node.children, inner, ctx)
    local text = inner.finish().text
    local id = href:match("^#(.+)$")
    local key = id and (id:match("^bib%-(.+)$") or id:match("^biblio%-(.+)$"))
    if key then
        b.mention(text, { kind = "reference", id = key })
    elseif id and ctx.ids[id] then
        b.mention(text, { kind = "section", section = id })
    elseif report_of(href) then
        b.mention(text, { kind = "report", id = report_of(href) })
    else
        b.append(text)
        local absolute = href:match("^https?://") and not href:match("^https?://www%.w3%.org/TR/")
        if absolute and squash(text) ~= href then
            b.append(" <" .. href .. ">")
        end
    end
end

--- Appends the children's inline text to the builder.
---@param children (rfc.source.html.Node|string)[]
---@param b table
---@param ctx rfc.source.html.Context
inline_into = function(children, b, ctx)
    for _, child in ipairs(children) do
        if type(child) == "string" then
            b.append(child)
        elseif not (M.dropped(child) or child.name == "del" or child.name == "img") then
            if child.name == "br" then
                b.hard_break()
            elseif child.name == "a" then
                anchor(child, b, ctx)
            elseif CODE[child.name] then
                b.append("`" .. squash(tree.plain(child)) .. "`")
            elseif child.name == "q" then
                b.append("“")
                inline_into(child.children, b, ctx)
                b.append("”")
            elseif child.name == "abbr" and child.attrs.title then
                inline_into(child.children, b, ctx)
                local title = child.attrs.title
                if not ctx.abbr[title] then
                    ctx.abbr[title] = true
                    b.append(" (" .. title .. ")")
                end
            elseif tree.BLOCK[child.name] then
                -- a block inside inline context (a cell holding paragraphs): its text, spaced
                b.append(" ")
                inline_into(child.children, b, ctx)
                b.append(" ")
            else
                inline_into(child.children, b, ctx)
            end
        end
    end
end

--- Reads the inline text of some children.
---@param children (rfc.source.html.Node|string)[]
---@param ctx rfc.source.html.Context
---@return rfc.source.html.Text
function M.inline(children, ctx)
    local b = builder()
    inline_into(children, b, ctx)
    return b.finish()
end

return M
