-- Inline text assembly and mention byte ranges.
--- Makes a text builder: pieces are appended with whitespace folded at the
--- seams, and mentions are recorded by their byte ranges in the finished text.
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

return builder
