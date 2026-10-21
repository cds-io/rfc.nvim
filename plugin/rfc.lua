-- Neovim calls in here: one command per source, and the help buffers that
-- are ours. :Rfc is the RFC Editor; :Eip is Ethereum's EIPs and ERCs, which
-- share one number space, so `:Eip 20` is ERC-20; :Bip is Bitcoin's BIPs.
-- Each takes a number, a tag, words to search its index, or nothing for its
-- picker, and completes by number or title over what is cached.
local function define(name, prefix, desc)
    vim.api.nvim_create_user_command(name, function(cmd)
        local run, _ = require("rfc").command(require("rfc.sources")[prefix])
        run(cmd)
    end, {
        nargs = "*",
        complete = function(arglead)
            local _, complete = require("rfc").command(require("rfc.sources")[prefix])
            return complete(arglead)
        end,
        desc = desc,
    })
end

define("Rfc", "rfc", "Open an RFC as help: a number, a tag, a search, or nothing for the index")
define("Eip", "eip", "Open an EIP or ERC as help: a number, a tag, a search, or nothing for the index")
define("Bip", "bip", "Open a BIP as help: a number, a tag, a search, or nothing for the index")

vim.api.nvim_create_autocmd("FileType", {
    pattern = "help",
    group = vim.api.nvim_create_augroup("rfc", { clear = true }),
    callback = function(args)
        require("rfc").attach(args.buf)
    end,
})
