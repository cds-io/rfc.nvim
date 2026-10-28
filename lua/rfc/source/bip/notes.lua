-- MediaWiki reference collection.
local plain = require("rfc.source.bip.inline").plain
local trim = function(s)
    return (s:match("^%s*(.-)%s*$"))
end
local M = {}

--- Collects the footnotes: every <ref>text</ref> is replaced by its number in
--- brackets, in order of first use; a named ref used again by <ref name="x" />
--- keeps its number; a ref closed on a later line takes the lines between into
--- its text and leaves them empty. The notes' text comes back plain.
---@param lines string[]
---@return string[] lines   -- the same count, markers in place of refs
---@return rfc.source.bip.Note[] notes
function M.footnotes(lines)
    local out, notes, named = {}, {}, {}
    local open = nil
    local function note(name, text)
        local n = name and named[name]
        if not n then
            n = #notes + 1
            notes[n] = { n = n, text = trim(plain(trim(text))) }
            if name then
                named[name] = n
            end
        end
        return " [" .. n .. "]"
    end
    for i, line in ipairs(lines) do
        local done, rest = "", line
        if open then
            local before, after = rest:match("^(.-)</ref>(.*)$")
            if before then
                table.insert(open.parts, before)
                notes[open.n].text = trim(plain(trim(table.concat(open.parts, " "))))
                open, rest = nil, after
            else
                table.insert(open.parts, rest)
                rest = ""
            end
        end
        while rest ~= "" do
            -- <ref> or <ref name=...>; <references /> is no ref
            local s, e, attrs = rest:find("<ref(%s[^>]*)>")
            local bare_s, bare_e = rest:find("<ref>", 1, true)
            if bare_s and (not s or bare_s < s) then
                s, e, attrs = bare_s, bare_e, ""
            end
            if not s then
                break
            end
            local name = attrs:match('name%s*=%s*"([^"]*)"') or attrs:match("name%s*=%s*([^%s/]+)")
            done = done .. rest:sub(1, s - 1)
            if attrs:match("/%s*$") then
                done = done .. note(name, "")
                rest = rest:sub(e + 1)
            else
                local text, after = rest:sub(e + 1):match("^(.-)</ref>(.*)$")
                if text then
                    done = done .. note(name, text)
                    rest = after
                else
                    done = done .. note(name, "")
                    open = { n = #notes, parts = { rest:sub(e + 1) } }
                    rest = ""
                end
            end
        end
        out[i] = done .. rest
    end
    return out, notes
end

return M
