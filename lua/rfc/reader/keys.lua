-- Shared document key bindings with explicit actions.
---@class rfc.ReaderActions
---@field follow fun(line: boolean)
---@field back fun()
---@field step fun(count: integer)
---@field toggle_toc fun(win: integer)
---@field cancel fun(win: integer)
---@field target fun(first: boolean): string|nil

--- The reader's keys in a document buffer, over the reader's actions.
---@param buf integer
---@param actions rfc.ReaderActions
return function(buf, actions)
    local follow, back, step, toggle_toc = actions.follow, actions.back, actions.step, actions.toggle_toc
    local cancel, target = actions.cancel, actions.target
    local bindings = {
        {
            "<C-]>",
            function()
                follow(false)
            end,
        },
        {
            "<CR>",
            function()
                follow(true)
            end,
        },
        { "<C-T>", back },
        {
            "]]",
            function()
                step(vim.v.count1)
            end,
        },
        {
            "[[",
            function()
                step(-vim.v.count1)
            end,
        },
        {
            "gO",
            function()
                toggle_toc(vim.api.nvim_get_current_win())
            end,
        },
        {
            "q",
            function()
                cancel(vim.api.nvim_get_current_win())
                require("cds.window").close_or(vim.api.nvim_get_current_win(), function()
                    vim.cmd.enew()
                end)
            end,
        },
        {
            "gx",
            function()
                local link = target(false)
                if link then
                    vim.ui.open(link)
                end
            end,
        },
    }
    require("cds.fp").each(bindings, function(binding)
        vim.keymap.set("n", binding[1], binding[2], { buffer = buf, desc = "rfc: document navigation" })
    end)
end
