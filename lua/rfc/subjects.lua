-- A source's subjects as a help document: the forest cds.subjects builds,
-- written as a contents block (one row per node, indented two spaces per
-- level, which is where the outline reads a heading's level) and then one
-- section per node, its heading the node's path with a tag at the margin
-- and its body the documents filed there as links. render is pure and
-- total; the store writes the document and `:help` does the rest.
local help = require("rfc.help")

local M = {}

---@class rfc.SubjectsDoc
---@field prefix string   -- rfc
---@field title string    -- RFCs by subject
---@field about string    -- the line naming the data

--- The tag of a node: the file tag, then each level slugged, dash-joined.
---@param prefix string
---@param path string[]
---@return string
function M.tag(prefix, path)
    local parts = { prefix .. "-subjects" }
    for _, name in ipairs(path) do
        table.insert(parts, help.slug(name))
    end
    return table.concat(parts, "-")
end

--- The nodes in pre-order, each with the tag it gets: a path's slug, or
--- the slug numbered when an earlier node took it (WHOIS and WHOIS++ slug
--- the same), so the tags file never holds one tag twice.
---@param prefix string
---@param forest cds.subjects.Node[]
---@return { node: cds.subjects.Node, tag: string }[]
function M.nodes(prefix, forest)
    local out, taken = {}, {}
    local function visit(node)
        local tag = M.tag(prefix, node.path)
        local n = 1
        while taken[tag] do
            n = n + 1
            tag = M.tag(prefix, node.path) .. "-" .. n
        end
        taken[tag] = true
        table.insert(out, { node = node, tag = tag })
        for _, child in ipairs(node.children) do
            visit(child)
        end
    end
    for _, root in ipairs(forest) do
        visit(root)
    end
    return out
end

--- The document: the title line with the file tags, the about line, a
--- blank, the contents block, a blank, the sections (heading, entries,
--- blank), the modeline and the footer. A node with no direct entries
--- still has its heading, since the sidebar lists it.
---@param doc rfc.SubjectsDoc
---@param forest cds.subjects.Node[]
---@return rfc.HelpDoc
function M.render(doc, forest)
    local file_tag = doc.prefix .. "-subjects"
    local out = { help.with_tag("*" .. file_tag .. ".txt*  " .. doc.title, file_tag), doc.about, "" }
    local tags = { { name = file_tag, line = 1 }, { name = file_tag .. ".txt", line = 1 } }
    local nodes = M.nodes(doc.prefix, forest)
    for _, n in ipairs(nodes) do
        local indent = ("  "):rep(#n.node.path - 1)
        table.insert(out, ("%s|%s|  %s (%d)"):format(indent, n.tag, n.node.name, #n.node.entries))
    end
    table.insert(out, "")
    for _, n in ipairs(nodes) do
        local heading = ("%s  (%d)"):format(table.concat(n.node.path, " / "), #n.node.entries)
        table.insert(out, help.with_tag(heading, n.tag))
        table.insert(tags, { name = n.tag, line = #out })
        for _, e in ipairs(n.node.entries) do
            table.insert(out, ("|%s%s|  %s"):format(doc.prefix, e.id, e.label))
        end
        table.insert(out, "")
    end
    table.insert(out, help.MODELINE)
    table.insert(out, help.FOOTER)
    return { lines = out, tags = tags }
end

return M
