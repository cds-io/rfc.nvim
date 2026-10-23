-- The subjects a source files its documents under, as entries and the
-- forest they form: a path is a list of names, root first, and a node is
-- every prefix of every path. The RFC Editor's subject tags are read from
-- their published CSV; any other source builds entries from whatever
-- categories it has. Plain lines in, plain tables out; nothing here names
-- the editor.
local csv = require("cds.csv")

local M = {}

---@class cds.subjects.Entry
---@field id string          -- "9110"
---@field label string       -- "HTTP Semantics (2022)"
---@field paths string[][]   -- every path given, root first
---@field direct string[][]  -- the paths the entry is listed under

---@class cds.subjects.Node
---@field name string
---@field path string[]
---@field children cds.subjects.Node[]   -- sorted by name, case-insensitively
---@field entries cds.subjects.Entry[]   -- the entries whose direct holds this path, sorted by number

---@param path string[]
---@return string
local function key(path)
  return table.concat(path, "\0")
end

--- Whether `prefix` is a proper prefix of `path`.
---@param prefix string[]
---@param path string[]
---@return boolean
local function extends(path, prefix)
  if #path <= #prefix then
    return false
  end
  for i, name in ipairs(prefix) do
    if path[i] ~= name then
      return false
    end
  end
  return true
end

--- An entry listed under the given paths that no other given path extends.
---@param id string
---@param label string
---@param paths string[][]
---@return cds.subjects.Entry
function M.entry(id, label, paths)
  local direct = {}
  for _, p in ipairs(paths) do
    local leaf = true
    for _, q in ipairs(paths) do
      leaf = leaf and not extends(q, p)
    end
    if leaf then
      table.insert(direct, p)
    end
  end
  return { id = id, label = label, paths = paths, direct = direct }
end

---@param s string
---@param sep string   -- a plain separator
---@return string[]
local function split(s, sep)
  local out = {}
  if s == "" then
    return out
  end
  local from = 1
  while true do
    local first, last = s:find(sep, from, true)
    if not first then
      table.insert(out, s:sub(from))
      return out
    end
    table.insert(out, s:sub(from, first - 1))
    from = last + 1
  end
end

--- The RFC Editor's rfc-tags.csv as entries: the number without its
--- prefix, the title and year as the label, the `paths` column as the
--- paths, and each name in `tags` resolved to the given path that ends in
--- it. A tag naming no path is dropped; a row left with no direct path is
--- omitted.
---@param lines string[]
---@return cds.subjects.Entry[]|nil
---@return string|nil err
function M.rfc(lines)
  local records, err = csv.records(lines)
  if not records then
    return nil, err
  end
  local entries = {}
  for _, r in ipairs(records) do
    local paths = {}
    for _, p in ipairs(split(r.paths or "", " | ")) do
      table.insert(paths, split(p, " / "))
    end
    local direct = {}
    for _, tag in ipairs(split(r.tags or "", ";")) do
      for _, p in ipairs(paths) do
        if p[#p] == tag then
          table.insert(direct, p)
          break
        end
      end
    end
    if #direct > 0 then
      table.insert(entries, {
        id = r.rfc:gsub("^RFC", ""),
        label = ("%s (%s)"):format(r.title, r.year),
        paths = paths,
        direct = direct,
      })
    end
  end
  return entries
end

---@param a { name: string }
---@param b { name: string }
---@return boolean
local function by_name(a, b)
  return a.name:lower() < b.name:lower()
end

---@param a cds.subjects.Entry
---@param b cds.subjects.Entry
---@return boolean
local function by_number(a, b)
  return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
end

--- The forest of every path prefix the entries name, each entry listed
--- under its direct paths, children and entries sorted; the roots named
--- in `order` come first, in that order, the rest after by name.
---@param entries cds.subjects.Entry[]
---@param order? string[]
---@return cds.subjects.Node[]
function M.tree(entries, order)
  local nodes, roots = {}, {}
  local function node_at(path)
    local k = key(path)
    if not nodes[k] then
      local node = { name = path[#path], path = path, children = {}, entries = {} }
      nodes[k] = node
      if #path == 1 then
        table.insert(roots, node)
      else
        local parent = node_at({ unpack(path, 1, #path - 1) })
        table.insert(parent.children, node)
      end
    end
    return nodes[k]
  end
  for _, e in ipairs(entries) do
    for _, p in ipairs(e.paths) do
      node_at(p)
    end
    for _, p in ipairs(e.direct) do
      table.insert(node_at(p).entries, e)
    end
  end
  for _, node in pairs(nodes) do
    table.sort(node.children, by_name)
    table.sort(node.entries, by_number)
  end
  local rank = {}
  for i, name in ipairs(order or {}) do
    rank[name] = i
  end
  table.sort(roots, function(a, b)
    local ra, rb = rank[a.name], rank[b.name]
    if ra and rb then
      return ra < rb
    elseif ra or rb then
      return ra ~= nil
    end
    return by_name(a, b)
  end)
  return roots
end

return M
