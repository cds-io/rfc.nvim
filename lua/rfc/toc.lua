-- Contents-specific presentation and help navigation over a window-owned
-- cds companion. The library owns splits, handles, event subscriptions and
-- teardown; RFC owns headings, selection and tag-stack navigation.
local config = require("rfc.config")
local outline = require("rfc.outline")
local view = require("rfc.view")
local M = {}
local ns = vim.api.nvim_create_namespace("rfc.toc")
local contents

---@param s cds.CompanionView
local function place(s)
    local i = outline.at(s.data.headings, vim.api.nvim_win_get_cursor(s.owner)[1])
    if i then
        vim.api.nvim_win_set_cursor(s.win, { i, 0 })
    end
end

---@param s cds.CompanionView
---@param doc_buf integer
local function load(s, doc_buf)
    s.data.headings = view.headings(doc_buf)
    local rows = outline.rows(s.data.headings)
    vim.bo[s.buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, rows.lines)
    vim.bo[s.buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
    for i, span in pairs(rows.labels) do
        vim.api.nvim_buf_set_extmark(s.buf, ns, i - 1, span[1], { end_col = span[2], hl_group = "rfcHeading" })
    end
    -- Two windows on one document have independent sidebars and selections.
    pcall(
        vim.api.nvim_buf_set_name,
        s.buf,
        "contents: " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(doc_buf), ":t:r")
    )
    place(s)
end

contents = require("cds.companion").new({
    filetype = "rfc-toc",
    width = function()
        return config.get().toc.width
    end,
    window = { winfixwidth = true, cursorline = true, spell = false, wrap = true },
    accept = function(buf)
        if vim.bo[buf].filetype == "" and vim.api.nvim_buf_get_name(buf) == "" then
            return nil
        end
        return require("rfc").owns(buf)
            and (vim.bo[buf].filetype == "help" or require("rfc").document_model(buf) ~= nil)
    end,
    on_update = load,
    on_track = place,
    on_create = function(s)
        vim.keymap.set("n", "<CR>", function()
            M.follow(s.owner)
        end, { buffer = s.buf, desc = "rfc: open the section" })
        for _, key in ipairs({ "q", "gO" }) do
            vim.keymap.set("n", key, function()
                M.close(s.owner)
            end, { buffer = s.buf, desc = "rfc: close the contents" })
        end
    end,
})

---@param doc_win integer
function M.close(doc_win)
    contents:close(doc_win)
end

---@param doc_win integer
---@return integer|nil
function M.window(doc_win)
    local s = contents:get(doc_win)
    return s and s.win or nil
end

---@param doc_win integer
function M.reload(doc_win)
    contents:refresh(doc_win)
end

---@param doc_win integer
function M.track(doc_win)
    contents:track(doc_win)
end

--- Follow the selected row's help tag in the owning document window, so its
--- tag stack grows and CTRL-T returns to the previous section.
---@param doc_win integer
function M.follow(doc_win)
    local s = contents:get(doc_win)
    if not s then
        return
    end
    local h = s.data.headings[vim.api.nvim_win_get_cursor(s.win)[1]]
    if not h then
        return
    end
    vim.api.nvim_win_call(doc_win, function()
        require("rfc").jump(h.tag)
    end)
    vim.api.nvim_set_current_win(doc_win)
end

---@param doc_win integer
function M.open(doc_win)
    contents:open(doc_win)
end

---@param doc_win integer
function M.toggle(doc_win)
    contents:toggle(doc_win)
end

function M.close_all()
    contents:close_all()
end

return M
