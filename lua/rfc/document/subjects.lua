-- Markdown projection of subjects source plans.

local builder = require("rfc.document.builder")
return function(model)
    local doc = builder.new(model)
    local put, prose, heading = doc.put, doc.prose, doc.heading
    put(prose(model.doc.about))
    put("")
    for _, node in ipairs(model.nodes) do
        put(
            string.rep("  ", #node.node.path - 1)
                .. "["
                .. node.tag
                .. "](rfc-tag:"
                .. node.tag
                .. ")  "
                .. prose(node.node.name)
                .. " ("
                .. node.count
                .. ")"
        )
    end
    put("")
    for _, node in ipairs(model.nodes) do
        heading(node.tag, node.node.name .. "  (" .. node.count .. ")", #node.node.path)
        for _, entry in ipairs(node.node.entries) do
            local tag = model.doc.prefix .. (model.doc.key == "shortname" and "-" or "") .. entry.id
            put("[" .. tag .. "](rfc-tag:" .. tag .. ")  " .. prose(entry.label))
        end
        put("")
    end
    return doc.finish()
end
