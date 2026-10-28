-- Markdown projection of proposal source plans.
local proposal = require("rfc.proposal.inline")
local builder = require("rfc.document.builder")
return function(model)
    local doc = builder.new(model)
    local put, prose, heading = doc.put, doc.prose, doc.heading
    for _, line in ipairs(model.header) do
        put(proposal.format(line, function(tag)
            return "[" .. tag .. "](rfc-tag:" .. tag .. ")"
        end, prose))
    end
    put("")
    local function inline(text)
        return proposal.format(model.inlines[text], function(tag)
            return "[" .. tag .. "](rfc-tag:" .. tag .. ")"
        end, prose)
    end
    if next(model.body.tags) then
        put("CONTENTS")
        for _, block in ipairs(model.blocks) do
            if block.kind == "heading" then
                put(
                    string.rep("  ", block.level - model.body.top + 1)
                        .. "["
                        .. model.body.tags[block]
                        .. "](rfc-tag:"
                        .. model.body.tags[block]
                        .. ")  "
                        .. prose(block.title)
                )
            end
        end
        put("")
    end
    for _, block in ipairs(model.blocks) do
        if block.kind == "heading" then
            heading(model.body.tags[block], model.body.texts[block], block.level)
        elseif block.kind == "fence" then
            local longest = 2
            for _, line in ipairs(block.code) do
                local run = line:match("^ *(`+)")
                longest = math.max(longest, run and #run or 0)
            end
            local mark = string.rep("`", longest + 1)
            put(mark .. (block.lang or ""))
            for _, line in ipairs(block.code) do
                put(line)
            end
            put(mark)
        elseif block.kind == "table" then
            if block.caption then
                put(prose(block.caption))
            end
            local width = 0
            for _, row in ipairs(block.rows) do
                width = math.max(width, #row)
            end
            local function row(cells)
                local rendered = {}
                for i = 1, width do
                    rendered[i] = inline(cells[i] or ""):gsub("|", "\\|")
                end
                put("| " .. table.concat(rendered, " | ") .. " |")
            end
            if not block.header then
                row({})
            end
            for i, cells in ipairs(block.rows) do
                row(cells)
                if i == 1 then
                    local rule = {}
                    for j = 1, width do
                        rule[j] = "---"
                    end
                    put("| " .. table.concat(rule, " | ") .. " |")
                end
            end
        elseif block.kind == "notes" then
            for _, note in ipairs(block.notes) do
                put("[" .. note.n .. "] " .. inline(note.text))
            end
        else
            put(inline(block.text))
        end
    end
    put("")
    return doc.finish()
end
