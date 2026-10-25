-- Scans a report's HTML into tokens: a tag with the few attributes the reader
-- uses, or the text between tags with its entities decoded and its whitespace
-- as written (`pre` needs it). The generators write well-formed trees, so
-- this scans for tags and repairs nothing.
local fp = require("cds.fp")

---@class rfc.source.html.tokens
local M = {}

---@class rfc.source.html.Token
---@field kind "open"|"close"|"text"
---@field name string|nil         -- open, close: the element name, lowercased
---@field attrs table<string, string>|nil  -- open: the attributes the reader uses
---@field void boolean|nil        -- open: a void element or one self-closed
---@field text string|nil         -- text: entities decoded, whitespace as written
---@field line integer            -- the source line the token starts on

-- The attributes kept on an open token; every other is dropped at the scan.
local KEPT = fp.set({ "class", "id", "href", "src", "alt", "title", "datetime", "data" })

-- Elements with no content and no closing tag.
local VOID = fp.set({ "br", "hr", "img", "input", "meta", "link", "wbr", "source", "col", "area", "base" })

-- Named entities the generators emit; a name outside this table stays as
-- written, since a reader that invents characters is worse than one that
-- shows the entity.
-- stylua: ignore
local ENTITIES = {
  amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ",
  hellip = "…", mdash = "—", ndash = "–", rarr = "→", larr = "←", times = "×",
  copy = "©", reg = "®", trade = "™", lsquo = "‘", rsquo = "’", ldquo = "“", rdquo = "”",
  laquo = "«", raquo = "»", middot = "·", bull = "•", deg = "°", plusmn = "±", para = "¶", sect = "§",
}

-- The three spellings of an attribute value: double-quoted, single-quoted,
-- bare. The first spelling that names an attribute wins.
local VALUE_FORMS = {
    '([%w%-]+)%s*=%s*"([^"]*)"',
    "([%w%-]+)%s*=%s*'([^']*)'",
    "([%w%-]+)%s*=%s*([^%s\"'][^%s>]*)",
}

--- Encodes a code point as UTF-8 (Lua 5.1 has no utf8 library).
---@param code integer
---@return string
local function utf8(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(
        0xF0 + math.floor(code / 0x40000),
        0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40,
        0x80 + code % 0x40
    )
end

--- Decodes the text's entities: the named ones above, `&#NNN;` and `&#xHH;`; a
--- non-breaking space becomes a space.
---@param s string
---@return string
function M.decode(s)
    return (
        s:gsub("&(#?x?)(%w+);", function(form, body)
            if form == "#" then
                return body:match("^%d+$") and utf8(assert(tonumber(body))) or nil
            elseif form == "#x" then
                return body:match("^%x+$") and utf8(tonumber(body, 16)) or nil
            end
            return ENTITIES[body]
        end)
    )
end

--- Folds whitespace runs to one space and trims the ends.
---@param s string
---@return string
function M.squash(s)
    return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

--- Reads the attributes of a tag's inside (`a href="x" class=y`), keeping those
--- the reader uses.
---@param inside string
---@return table<string, string>
local function attributes(inside)
    local attrs = {}
    for _, form in ipairs(VALUE_FORMS) do
        for name, value in inside:gmatch(form) do
            local key = name:lower()
            if KEPT[key] and attrs[key] == nil then
                attrs[key] = M.decode(value)
            end
        end
    end
    return attrs
end

--- Scans a report into tokens. Comments, and `script` and `style` with their
--- contents, are skipped whole. A tag may span lines; the token's line is where
--- it starts.
---@param lines string[]
---@return rfc.source.html.Token[]
function M.tokens(lines)
    local s = table.concat(lines, "\n")
    local tokens, pos, line = {}, 1, 1
    local function advance(to)
        local _, newlines = s:sub(pos, to - 1):gsub("\n", "")
        line = line + newlines
        pos = to
    end
    local function text(from, to)
        if to >= from then
            table.insert(tokens, { kind = "text", text = M.decode(s:sub(from, to)), line = line })
        end
    end
    while pos <= #s do
        local lt = s:find("<", pos, true)
        if not lt then
            text(pos, #s)
            break
        end
        if lt > pos then
            text(pos, lt - 1)
            advance(lt)
        end
        if s:sub(lt, lt + 3) == "<!--" then
            local close = s:find("-->", lt + 4, true) or #s
            advance(close + 3)
        else
            local gt, quote
            for i = lt + 1, #s do
                local c = s:sub(i, i)
                if quote then
                    if c == quote then
                        quote = nil
                    end
                elseif c == '"' or c == "'" then
                    quote = c
                elseif c == ">" then
                    gt = i
                    break
                end
            end
            if not gt then
                text(lt, #s)
                break
            end
            local inside = s:sub(lt + 1, gt - 1)
            local closing, name = inside:match("^(/?)%s*([%a][%w%-]*)")
            if not name then
                -- a doctype or a stray <: not a tag
                advance(gt + 1)
            elseif closing == "/" then
                table.insert(tokens, { kind = "close", name = name:lower(), line = line })
                advance(gt + 1)
            else
                name = name:lower()
                local at = line
                local self_closed = inside:match("/%s*$") ~= nil
                advance(gt + 1)
                if name == "script" or name == "style" then
                    -- skipped whole, contents and all: a script holds markup-like
                    -- text; a self-closed one has no contents to skip
                    if not self_closed then
                        local stop = s:find("</" .. name, pos, true) or s:lower():find("</" .. name, pos, true)
                        advance(stop and (s:find(">", stop, true) or #s) + 1 or #s + 1)
                    end
                else
                    local token = { kind = "open", name = name, attrs = attributes(inside:sub(#name + 1)), line = at }
                    if VOID[name] or self_closed then
                        token.void = true
                    end
                    table.insert(tokens, token)
                end
            end
        end
    end
    return tokens
end

return M
