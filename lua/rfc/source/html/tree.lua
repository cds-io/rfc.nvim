-- Builds the element tree from the tokens and answers the questions a reader
-- asks of a node: its classes, its plain text, the first or every node that
-- passes a test. A close tag pops to the nearest open element of its name,
-- and the end tags the generators leave out are supplied by the rules below.
local fp = require("cds.fp")
local tokens = require("rfc.source.html.tokens")

---@class rfc.source.html.tree
local M = {}

---@class rfc.source.html.Node
---@field name string
---@field attrs table<string, string>
---@field children (rfc.source.html.Node|string)[]
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

--- Builds the tree of the tokens under one root.
---@param toks rfc.source.html.Token[]
---@return rfc.source.html.Node
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

--- Builds the tree of a report's lines.
---@param lines string[]
---@return rfc.source.html.Node
function M.of(lines)
    return M.tree(tokens.tokens(lines))
end

--- Whether a child is an element (and not a text string).
---@param child rfc.source.html.Node|string
---@return boolean
function M.is_element(child)
    return type(child) ~= "string"
end

--- Makes a test for an element of the name.
---@param name string
---@return fun(child: rfc.source.html.Node|string): boolean
function M.named(name)
    return function(child)
        return type(child) ~= "string" and child.name == name
    end
end

---@param node rfc.source.html.Node
---@return table<string, boolean>
function M.classes(node)
    local set = {}
    for c in (node.attrs.class or ""):gmatch("%S+") do
        set[c] = true
    end
    return set
end

--- Makes a test for an element carrying the class.
---@param class string
---@return fun(child: rfc.source.html.Node|string): boolean
function M.classed(class)
    return function(child)
        return type(child) ~= "string" and M.classes(child)[class] == true
    end
end

--- Joins every string under a node: what a label is before squashing.
---@param node rfc.source.html.Node|string
---@return string
function M.plain(node)
    if type(node) == "string" then
        return node
    end
    return table.concat(fp.map(node.children, M.plain), "")
end

--- Finds the first child that passes the test and answers it with the other
--- children in order. The tests given here (`named`, `classed`) answer only for
--- elements, so what is found is a node.
---@param children (rfc.source.html.Node|string)[]
---@param test fun(child: rfc.source.html.Node|string): any
---@return rfc.source.html.Node|nil found
---@return (rfc.source.html.Node|string)[] rest
function M.split(children, test)
    local found = fp.find(children, test) --[[@as rfc.source.html.Node?]]
    local rest = fp.filter(children, function(c)
        return c ~= found
    end)
    return found, rest
end

--- Finds every node under `root` that passes the test, in document order.
---@param root rfc.source.html.Node
---@param test fun(node: rfc.source.html.Node): boolean
---@return rfc.source.html.Node[]
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

--- Finds the first node under `root` that passes the test, and its parent.
---@param root rfc.source.html.Node
---@param test fun(node: rfc.source.html.Node): boolean
---@return rfc.source.html.Node|nil
---@return rfc.source.html.Node|nil parent
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

--- Finds the first node under `root` with the id, and its parent.
---@param root rfc.source.html.Node
---@param id string
---@return rfc.source.html.Node|nil
---@return rfc.source.html.Node|nil parent
function M.by_id(root, id)
    return M.find_first(root, function(n)
        return n.attrs.id == id
    end)
end

return M
