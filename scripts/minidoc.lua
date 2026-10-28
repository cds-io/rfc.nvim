-- Generates doc/rfc.txt with mini.doc (`make doc`): the manual is the
-- annotation blocks in doc/manual.lua and the rfc.Config class with its
-- defaults in lua/rfc/config.lua.
-- A block is kept only when it carries a tag, a class, the contents or an
-- eval; the doc comments on the rims' functions stay out of the help file,
-- since they document the code, and the help is for the reader.
require("mini.doc").setup({ silent = true })

local KEPT = { ["@tag"] = true, ["@class"] = true, ["@toc"] = true, ["@eval"] = true }

---@param block table   -- a mini.doc block: an array of sections
---@return boolean
local function kept(block)
    for _, section in ipairs(block) do
        if KEPT[section.info.id] then
            return true
        end
    end
    return false
end

-- the house writes a parameter's note after ` -- `; the help reads it as the
-- description, without the dashes
local NOTED = { ["@param"] = true, ["@field"] = true, ["@return"] = true }

MiniDoc.generate({ "doc/manual.lua", "lua/rfc/config.lua" }, "doc/rfc.txt", {
    hooks = {
        -- every kept block names its own tag and signature, so nothing is
        -- inferred from the code below it
        block_pre = function(block)
            if not kept(block) then
                block:clear_lines()
            end
        end,
        section_pre = function(section)
            if NOTED[section.info.id] then
                section[1] = section[1]:gsub("%s+%-%-%s+", " ", 1)
            end
            MiniDoc.default_hooks.section_pre(section)
        end,
    },
})
