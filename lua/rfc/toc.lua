-- The contents sidebar: a scratch window beside a document's help window
-- listing its headings, its cursor on the section the reader is in. The
-- model is one record per document window (the sidebar's lifetime is that
-- window's), dropped in one place, close, whichever side goes first. Enter
-- on a row is :help on the row's tag in the document window, so the tag
-- stack grows and CTRL-T comes back.
local config = require("rfc.config")
local outline = require("rfc.outline")
local fp = require("cds.fp")
local view = require("rfc.view")

local M = {}

local ns = vim.api.nvim_create_namespace("rfc.toc")

---@class rfc.Sidebar
---@field win integer
---@field buf integer
---@field doc_win integer
---@field doc_buf integer
---@field headings rfc.Heading[]
---@field group integer

---@type table<integer, rfc.Sidebar>  -- by document window
local open = {}

--- The sidebar's cursor on the row of the section holding the document's
--- cursor; left where it is above the first heading.
---@param s rfc.Sidebar
local function place(s)
    local i = outline.at(s.headings, vim.api.nvim_win_get_cursor(s.doc_win)[1])
    if i then
        vim.api.nvim_win_set_cursor(s.win, { i, 0 })
    end
end

--- The rows of the document the sidebar's window shows, written into it.
---@param s rfc.Sidebar
---@param doc_buf integer
local function load(s, doc_buf)
    s.doc_buf = doc_buf
    s.headings = view.headings(doc_buf)
    local rows = outline.rows(s.headings)
    vim.bo[s.buf].modifiable = true
    vim.api.nvim_buf_set_lines(s.buf, 0, -1, false, rows.lines)
    vim.bo[s.buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(s.buf, ns, 0, -1)
    for i, span in pairs(rows.labels) do
        vim.api.nvim_buf_set_extmark(s.buf, ns, i - 1, span[1], { end_col = span[2], hl_group = "rfcHeading" })
    end
    -- two sidebars on one document would want one name; the second keeps its old one
    pcall(
        vim.api.nvim_buf_set_name,
        s.buf,
        "contents: " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(doc_buf), ":t:r")
    )
    place(s)
end

--- Forgets the sidebar: the record and its autocmds go; the window is the
--- caller's to close, since the one closing from inside WinClosed must wait.
---@param doc_win integer
---@return rfc.Sidebar|nil
local function drop(doc_win)
    local s = open[doc_win]
    if not s then
        return nil
    end
    open[doc_win] = nil
    pcall(vim.api.nvim_del_augroup_by_id, s.group)
    return s
end

--- Whether the tab has a window other than `win` that is no floating
--- window; a floating one (a notifier's toast) cannot be the last window
--- left, so it does not count.
---@param win integer
---@return boolean
local function others(win)
    return fp.any(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)), function(w)
        return w ~= win and vim.api.nvim_win_get_config(w).relative == ""
    end)
end

--- Closes the sidebar's window; the last window of its tab cannot close, so
--- that one is given an empty buffer and its sidebar options taken back.
---@param s rfc.Sidebar
local function close_window(s)
    if not vim.api.nvim_win_is_valid(s.win) then
        return
    end
    if others(s.win) then
        vim.api.nvim_win_close(s.win, true)
        return
    end
    vim.api.nvim_win_set_buf(s.win, vim.api.nvim_create_buf(true, false))
    vim.wo[s.win].winfixwidth = false
    vim.wo[s.win].cursorline = vim.go.cursorline
    vim.wo[s.win].wrap = vim.go.wrap
    vim.wo[s.win].spell = vim.go.spell
end

---@param doc_win integer
function M.close(doc_win)
    local s = drop(doc_win)
    if s then
        close_window(s)
    end
end

--- The sidebar's window for a document window, when one is open.
---@param doc_win integer
---@return integer|nil
function M.window(doc_win)
    return open[doc_win] and open[doc_win].win or nil
end

--- The rows again from the document, after it is rendered anew in its
--- window; nothing when the window has no sidebar.
---@param doc_win integer
function M.reload(doc_win)
    local s = open[doc_win]
    if s and vim.api.nvim_win_is_valid(doc_win) then
        load(s, vim.api.nvim_win_get_buf(doc_win))
    end
end

--- The sidebar's cursor follows the document's, unless the reader is in
--- the sidebar.
---@param doc_win integer
function M.track(doc_win)
    local s = open[doc_win]
    if s and vim.api.nvim_get_current_win() ~= s.win then
        place(s)
    end
end

--- :help on the row's tag, in the document window, then the cursor there.
---@param doc_win integer
function M.follow(doc_win)
    local s = open[doc_win]
    if not s then
        return
    end
    local h = s.headings[vim.api.nvim_win_get_cursor(s.win)[1]]
    if not h or not vim.api.nvim_win_is_valid(doc_win) then
        return
    end
    vim.api.nvim_win_call(doc_win, function()
        require("rfc").jump(h.tag)
    end)
    vim.api.nvim_set_current_win(doc_win)
end

--- Opens the sidebar for the document in `doc_win` and puts the cursor in it.
---@param doc_win integer
function M.open(doc_win)
    if open[doc_win] then
        return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "rfc-toc"
    local win = vim.api.nvim_open_win(buf, true, { split = "right", width = config.get().toc.width, win = doc_win })
    vim.wo[win].winfixwidth = true
    vim.wo[win].cursorline = true
    vim.wo[win].spell = false
    vim.wo[win].wrap = true
    local group = vim.api.nvim_create_augroup("rfc.toc." .. doc_win, { clear = true })
    ---@type rfc.Sidebar
    local s = { win = win, buf = buf, doc_win = doc_win, doc_buf = 0, headings = {}, group = group }
    open[doc_win] = s
    load(s, vim.api.nvim_win_get_buf(doc_win))

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        callback = function()
            if vim.api.nvim_get_current_win() == doc_win then
                M.track(doc_win)
            end
        end,
    })
    -- the document window turning to another buffer: one of ours is loaded
    -- into the rows, a buffer still being set up is looked at again once it
    -- is, anything else closes the sidebar
    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        callback = function(args)
            if not vim.api.nvim_win_is_valid(doc_win) or vim.api.nvim_win_get_buf(doc_win) ~= args.buf then
                return
            end
            if args.buf == s.doc_buf then
                M.track(doc_win)
                return
            end
            local function settle()
                if open[doc_win] ~= s or not vim.api.nvim_win_is_valid(doc_win) then
                    return
                end
                if vim.api.nvim_win_get_buf(doc_win) ~= args.buf then
                    return
                end
                if vim.bo[args.buf].filetype == "help" and require("rfc").owns(args.buf) then
                    load(s, args.buf)
                else
                    M.close(doc_win)
                end
            end
            if vim.bo[args.buf].filetype == "" and vim.api.nvim_buf_get_name(args.buf) == "" then
                vim.schedule(settle)
            else
                settle()
            end
        end,
    })
    -- closing the sidebar from inside the document's WinClosed, when the two
    -- are the tab's last windows, aborts the :q that started it (E855); the
    -- record goes now and the window on the next turn of the loop
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(doc_win),
        callback = function()
            local gone = drop(doc_win)
            if gone then
                vim.schedule(function()
                    close_window(gone)
                end)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        pattern = tostring(win),
        callback = function()
            drop(doc_win)
        end,
    })

    vim.keymap.set("n", "<CR>", function()
        M.follow(doc_win)
    end, { buffer = buf, desc = "rfc: open the section" })
    vim.keymap.set("n", "q", function()
        M.close(doc_win)
    end, { buffer = buf, desc = "rfc: close the contents" })
    vim.keymap.set("n", "gO", function()
        M.close(doc_win)
    end, { buffer = buf, desc = "rfc: close the contents" })
end

---@param doc_win integer
function M.toggle(doc_win)
    if open[doc_win] then
        M.close(doc_win)
    else
        M.open(doc_win)
    end
end

--- Every sidebar closed; for a fixture's teardown.
function M.close_all()
    for doc_win in pairs(open) do
        M.close(doc_win)
    end
end

return M
