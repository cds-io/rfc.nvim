-- Markdown projection of rfc source plans.
local help = require("rfc.help.model")
local builder = require("rfc.document.builder")
return function(model)
    local doc = builder.new(model)
    local put, linked, heading = doc.put, doc.linked, doc.heading
    local anchors, out = doc.anchors, doc.lines
    local function depth(number)
        local count = 0
        for _ in number:gmatch("[^.]+") do
            count = count + 1
        end
        return math.max(count, 1)
    end
    for _, block in ipairs(model.blocks) do
        local text = linked(block.text, block.mentions, function(m)
            return help.target(m, model.context, block.citation)
        end)
        if block.kind == "heading" then
            heading(model.tag_of[block], block.text, depth(block.section.number), text)
        else
            if block.kind == "row" then
                local needle = block.section.label ~= "" and block.section.label or block.section.title
                local first, last = text:find(needle, 1, true)
                if first then
                    text = text:sub(1, first - 1)
                        .. "["
                        .. model.tag_of[block]
                        .. "](rfc-tag:"
                        .. model.tag_of[block]
                        .. ")"
                        .. text:sub(last + 1)
                end
            end
            put(text)
            if block.kind == "reference" and model.tag_of[block] then
                anchors[model.tag_of[block]] = #out
            end
        end
    end
    put("")
    return doc.finish()
end
