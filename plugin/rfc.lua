-- Neovim calls in here: the command, and the help buffers that are ours.
vim.api.nvim_create_user_command("Rfc", function(cmd)
    local rfc = require("rfc")
    local arg = cmd.args
    if arg == "" then
        rfc.pick()
    elseif arg:match("^%d+$") then
        rfc.open(arg)
    elseif arg:match("^rfc%d+") then
        rfc.jump(arg)
    else
        rfc.notify("usage: :Rfc [<number> | rfc<number>[-<section>]]", vim.log.levels.WARN)
    end
end, { nargs = "?", desc = "Open an RFC as help: a number, a tag, or nothing for the index" })

vim.api.nvim_create_autocmd("FileType", {
    pattern = "help",
    group = vim.api.nvim_create_augroup("rfc", { clear = true }),
    callback = function(args)
        require("rfc").attach(args.buf)
    end,
})
