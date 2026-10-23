-- The tokens as a tree, and the questions a reader asks of a node: its
-- classes, its plain text, the first or every node that answers a test.
-- A close tag pops to the nearest open element of its name; the end tags
-- the generators leave out are supplied by the rules below.
local fp = require("cds.fp")
local tokens = require("cds.html.tokens")

local M = {}

---@class cds.html.Node
---@field name string
---@field attrs table<string, string>
---@field children (cds.html.Node|string)[]
---@field line integer

-- Elements that open a block: one of these opening while a `p` is the
-- innermost element closes the `p`, since the generators omit `</p>`.
-- stylua: ignore
M.BLOCK = fp.set({
  "p", "div", "section", "article", "main", "header", "footer", "nav", "aside", "details", "figure",
  "figcaption", "ul", "ol", "li", "dl", "dt", "dd", "table", "thead", "tbody", "tfoot", "tr", "td", "th",
  "caption", "pre", "blockquote", "hr", "h1", "h2", "h3", "h4", "h5", "h6", "dialog", "form", "fieldset",
})

-- What an element's opening closes when it is the innermost: the end tags
-- Bikeshed leaves out.
local CLOSES = {
  body = fp.set({ "head" }),
  dt = fp.set({ "dt", "dd" }),
  dd = fp.set({ "dt", "dd" }),
  li = fp.set({ "li" }),
  tr = fp.set({ "tr", "td", "th" }),
  td = fp.set({ "td", "th" }),
  th = fp.set({ "td", "th" }),
  option = fp.set({ "option" }),
}

--- The tokens as a tree under one root.
---@param toks cds.html.Token[]
---@return cds.html.Node
function M.tree(toks)
  local root = { name = "#root", attrs = {}, children = {}, line = 1 }
  local stack = { root }
  for _, t in ipairs(toks) do
    if t.kind == "text" then
      table.insert(stack[#stack].children, t.text)
    elseif t.kind == "open" then
      local top = stack[#stack]
      if top.name == "p" and M.BLOCK[t.name] then
        table.remove(stack)
        top = stack[#stack]
      end
      while CLOSES[t.name] and CLOSES[t.name][top.name] do
        table.remove(stack)
        top = stack[#stack]
      end
      local node = { name = t.name, attrs = t.attrs, children = {}, line = t.line }
      table.insert(top.children, node)
      if not t.void then
        table.insert(stack, node)
      end
    else
      for i = #stack, 2, -1 do
        if stack[i].name == t.name then
          for _ = #stack, i, -1 do
            table.remove(stack)
          end
          break
        end
      end
    end
  end
  return root
end

--- The tree of a report's lines.
---@param lines string[]
---@return cds.html.Node
function M.of(lines)
  return M.tree(tokens.tokens(lines))
end

--- Whether a child is an element (and not a text string).
---@param child cds.html.Node|string
---@return boolean
function M.is_element(child)
  return type(child) ~= "string"
end

--- A test for an element of the name.
---@param name string
---@return fun(child: cds.html.Node|string): boolean
function M.named(name)
  return function(child)
    return type(child) ~= "string" and child.name == name
  end
end

---@param node cds.html.Node
---@return table<string, boolean>
function M.classes(node)
  local set = {}
  for c in (node.attrs.class or ""):gmatch("%S+") do
    set[c] = true
  end
  return set
end

--- A test for an element carrying the class.
---@param class string
---@return fun(child: cds.html.Node|string): boolean
function M.classed(class)
  return function(child)
    return type(child) ~= "string" and M.classes(child)[class] == true
  end
end

--- Every string under a node, joined: what a label is before squashing.
---@param node cds.html.Node|string
---@return string
function M.plain(node)
  if type(node) == "string" then
    return node
  end
  return table.concat(fp.map(node.children, M.plain), "")
end

--- The first child that answers the test, and the other children in order.
---@param children (cds.html.Node|string)[]
---@param test fun(child: cds.html.Node|string): boolean
---@return cds.html.Node|nil found
---@return (cds.html.Node|string)[] rest
function M.split(children, test)
  local found = fp.find(children, test)
  local rest = fp.filter(children, function(c)
    return c ~= found
  end)
  return found, rest
end

--- Every node under `root` that answers the test, in document order.
---@param root cds.html.Node
---@param test fun(node: cds.html.Node): boolean
---@return cds.html.Node[]
function M.find_all(root, test)
  local out = {}
  local function walk(node)
    for _, child in ipairs(node.children) do
      if type(child) ~= "string" then
        if test(child) then
          table.insert(out, child)
        end
        walk(child)
      end
    end
  end
  walk(root)
  return out
end

--- The first node under `root` that answers the test, and its parent.
---@param root cds.html.Node
---@param test fun(node: cds.html.Node): boolean
---@return cds.html.Node|nil
---@return cds.html.Node|nil parent
function M.find_first(root, test)
  local function walk(node)
    for _, child in ipairs(node.children) do
      if type(child) ~= "string" then
        if test(child) then
          return child, node
        end
        local found, parent = walk(child)
        if found then
          return found, parent
        end
      end
    end
  end
  return walk(root)
end

--- The first node under `root` with the id, and its parent.
---@param root cds.html.Node
---@param id string
---@return cds.html.Node|nil
---@return cds.html.Node|nil parent
function M.by_id(root, id)
  return M.find_first(root, function(n)
    return n.attrs.id == id
  end)
end

return M
