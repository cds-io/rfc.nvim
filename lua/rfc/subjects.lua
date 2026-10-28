---@class rfc.SubjectsModel
---@field kind "subjects"
---@field name string
---@field title string
---@field doc rfc.SubjectsDoc
---@field nodes { node: rfc.source.subjects.Node, tag: string, count: integer }[]

-- A source's subjects as a help document: the forest rfc.source.subjects builds,
-- written as a contents block (one row per node, indented two spaces per
-- level, which is where the outline reads a heading's level) and then one
-- section per node, its heading the node's path with a tag at the margin
-- and its body the documents filed there as links. render is pure and
-- total; the store writes the document and `:help` does the rest.
local tag_names = require("rfc.help.tags")
local help = require("rfc.help")
local fp = require("cds.fp")

local M = {}

---@class rfc.SubjectsDoc
---@field prefix string   -- rfc
---@field title string    -- RFCs by subject
---@field about string    -- the line naming the data
---@field key "number"|"shortname"|nil  -- how a document's tag joins the prefix and the id: rfc9110, or w3c-wcag22
---@field status string|nil  -- the status the document is filtered to, named in its title line; nil for All

--- What a status adds to the render version: +final; nothing for All.
---@param status string|nil
---@return string
function M.suffix(status)
    return status and ("+" .. tag_names.slug(status)) or ""
end

--- The tag of a node: the file tag, then each level slugged, dash-joined.
---@param prefix string
---@param path string[]
---@return string
function M.tag(prefix, path)
    local parts = fp.map(path, tag_names.slug)
    table.insert(parts, 1, prefix .. "-subjects")
    return table.concat(parts, "-")
end

--- The nodes in pre-order, each with the tag it gets: a path's slug, or
--- the slug numbered when an earlier node took it (WHOIS and WHOIS++ slug
--- the same), so the tags file never holds one tag twice.
---@param prefix string
---@param forest rfc.source.subjects.Node[]
---@return { node: rfc.source.subjects.Node, tag: string }[]
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

---@class rfc.SubjectNode
---@field tag string     -- rfc-subjects-web-http
---@field slug string    -- web-http: the tag without the file tag
---@field leaf string    -- http: the last level's slug
---@field path string    -- web / HTTP
---@field count integer  -- the documents under it

--- The nodes a rendered document declares, read back from its contents
--- block (the rows after the title, the about line and a blank, up to
--- the next blank): the path from the indent, the count from the row.
--- What completion and a node search work from, so they see exactly the
--- tags the document carries.
---@param lines string[]
---@return rfc.SubjectNode[]
function M.read_nodes(lines)
    local nodes, names = {}, {}
    for i = 4, #lines do
        local indent, tag, name, count = lines[i]:match("^(%s*)|([^|]+)|  (.*) %((%d+)%)$")
        if not tag then
            break
        end
        local depth = #indent / 2 + 1
        names[depth] = name
        for d = depth + 1, #names do
            names[d] = nil
        end
        table.insert(nodes, {
            tag = tag,
            slug = (tag:gsub("^%l[%l%d]-%l%-subjects%-", "")),
            leaf = tag_names.slug(name),
            path = table.concat(names, " / ", 1, depth),
            count = tonumber(count),
        })
    end
    return nodes
end

--- The documents under a node, its own and its descendants', each
--- counted once however many of its paths lie there: what a heading's
--- count means to a reader.
---@param node rfc.source.subjects.Node
---@return integer
function M.total(node)
    local seen, n = {}, 0
    local function visit(x)
        for _, e in ipairs(x.entries) do
            if not seen[e.id] then
                seen[e.id] = true
                n = n + 1
            end
        end
        for _, child in ipairs(x.children) do
            visit(child)
        end
    end
    visit(node)
    return n
end

--- The document: the title line with the file tags (and the status it is
--- filtered to, when one is), the about line, a blank, the contents block,
--- a blank, the sections (heading, entries, blank), the modeline and the
--- footer. A heading is the node's name
--- with the count of everything under it; the tag at its margin spells
--- the path, and so does the contents block's indent. A node with no
--- direct entries still has its heading, since the sidebar lists it.
---@param doc rfc.SubjectsDoc
---@param forest rfc.source.subjects.Node[]
---@return rfc.SubjectsModel
function M.model(doc, forest)
    local nodes = fp.map(M.nodes(doc.prefix, forest), function(n)
        return { node = n.node, tag = n.tag, count = M.total(n.node) }
    end)
    return {
        kind = "subjects",
        name = doc.prefix .. "-subjects",
        doc = doc,
        nodes = nodes,
        title = doc.title .. (doc.status and ("  [Status: " .. doc.status .. "]") or ""),
    }
end

---@param doc rfc.SubjectsDoc
---@param forest rfc.source.subjects.Node[]
---@return rfc.HelpDoc
function M.render(doc, forest)
    return M.render_model(M.model(doc, forest))
end

---@param model rfc.SubjectsModel
---@return rfc.HelpDoc
function M.render_model(model)
    local doc = model.doc
    local file_tag = model.name
    local title = "*"
        .. file_tag
        .. ".txt*  "
        .. doc.title
        .. (doc.status and ("  [Status: " .. doc.status .. "]") or "")
    local out = { help.with_tag(title, file_tag), doc.about, "" }
    local tags = { { name = file_tag, line = 1 }, { name = file_tag .. ".txt", line = 1 } }
    local nodes = model.nodes
    for _, n in ipairs(nodes) do
        local indent = ("  "):rep(#n.node.path - 1)
        table.insert(out, ("%s|%s|  %s (%d)"):format(indent, n.tag, n.node.name, n.count))
    end
    table.insert(out, "")
    for _, n in ipairs(nodes) do
        local heading = ("%s  (%d)"):format(n.node.name, n.count)
        table.insert(out, help.with_tag(heading, n.tag))
        table.insert(tags, { name = n.tag, line = #out })
        for _, e in ipairs(n.node.entries) do
            local tag = doc.key == "shortname" and (doc.prefix .. "-" .. e.id) or (doc.prefix .. e.id)
            table.insert(out, ("|%s|  %s"):format(tag, e.label))
        end
        table.insert(out, "")
    end
    table.insert(out, help.MODELINE)
    -- the footer names the render and the status, so a document rendered
    -- under another status reads as another version
    table.insert(out, help.FOOTER .. M.suffix(doc.status))
    return { lines = out, tags = tags, model = model }
end

return M
