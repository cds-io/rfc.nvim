-- A node's inline text: pieces appended with whitespace folded at the
-- seams, code in backticks, an abbreviation expanded once, and every link
-- a mention by its byte range: a section of the report, another report,
-- or a reference entry. Everything else is the text alone.
local fp = require("cds.fp")
local tree = require("cds.html.tree")
local tokens = require("cds.html.tokens")

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
---@param node cds.html.Node
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

---@class cds.html.Context
---@field ids table<string, boolean>    -- the ids of headings and sections
---@field abbr table<string, boolean>   -- the abbreviations already expanded
---@field section string|nil            -- the enclosing section's id

---@class cds.html.Text
---@field text string
---@field mentions cds.Mention[]

--- A text builder: pieces appended with whitespace folded at the seams,
--- and mentions recorded by their byte ranges in the finished text.
local function builder()
  local b = { parts = {}, len = 0, mentions = {}, pending_space = false }
  function b.append(piece)
    piece = piece:gsub("%s+", " ")
    if piece == "" then
      return
    end
    if piece:sub(1, 1) == " " then
      piece = piece:sub(2)
      b.pending_space = b.len > 0 and not b.ends_with_space
    end
    local trailing = piece:sub(-1) == " "
    if trailing then
      piece = piece:sub(1, -2)
    end
    if piece ~= "" then
      if b.pending_space and not b.ends_with_space and b.len > 0 then
        table.insert(b.parts, " ")
        b.len = b.len + 1
      end
      b.pending_space = false
      table.insert(b.parts, piece)
      b.len = b.len + #piece
      b.ends_with_space = false
    end
    if trailing then
      b.pending_space = b.len > 0
    end
  end
  function b.hard_break()
    table.insert(b.parts, "\n")
    b.len = b.len + 1
    b.pending_space = false
    b.ends_with_space = true
  end
  --- Appends a piece as a mention of `fields`, so its range is known.
  function b.mention(piece, fields)
    local before = b.len
    local lead = piece:match("^%s*")
    if lead ~= "" then
      b.append(lead)
    end
    local first = b.len + ((b.pending_space and b.len > 0 and not b.ends_with_space) and 2 or 1)
    b.append(piece)
    if b.len > before then
      fields.first = first
      fields.last = b.len
      table.insert(b.mentions, fields)
    end
  end
  function b.finish()
    return { text = table.concat(b.parts), mentions = b.mentions }
  end
  return b
end

local inline_into

--- The shortname of a fragment-free report URL, or nil.
---@param href string
---@return string|nil
local function report_of(href)
  return href:match("^https?://www%.w3%.org/TR/([^/#?]+)/?$")
end

--- An anchor appended to the builder as text, a mention, or text with its
--- URL once.
---@param node cds.html.Node
---@param b table
---@param ctx cds.html.Context
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
---@param children (cds.html.Node|string)[]
---@param b table
---@param ctx cds.html.Context
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

--- The inline text of some children.
---@param children (cds.html.Node|string)[]
---@param ctx cds.html.Context
---@return cds.html.Text
function M.inline(children, ctx)
  local b = builder()
  inline_into(children, b, ctx)
  return b.finish()
end

return M
