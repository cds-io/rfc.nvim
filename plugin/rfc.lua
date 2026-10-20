-- Neovim calls in here: the command, and the help buffers that are ours.
-- :Rfc takes a number (an RFC), a tag (rfc9110-3.1, eip1559, erc20), words
-- to search the indices by number or title, or nothing for the picker. A
-- completed item carries its title after the tag, so only the first word
-- is the tag.
vim.api.nvim_create_user_command("Rfc", function(cmd)
    local rfc = require("rfc")
    local arg = vim.trim(cmd.args)
    local first = arg:match("^(%S+)") or ""
    if arg == "" then
        rfc.pick()
    elseif first:match("^%d+$") then
        rfc.jump("rfc" .. first)
    elseif first:match("^%l+%d+") then
        rfc.jump(first)
    else
        rfc.pick(arg)
    end
end, {
    nargs = "*",
    complete = function(arglead)
        return require("rfc").complete(arglead)
    end,
    desc = "Open an RFC, EIP or ERC as help: a number, a tag, a search, or nothing for the index",
})

vim.api.nvim_create_autocmd("FileType", {
    pattern = "help",
    group = vim.api.nvim_create_augroup("rfc", { clear = true }),
    callback = function(args)
        require("rfc").attach(args.buf)
    end,
})
