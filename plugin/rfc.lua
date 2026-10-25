-- Neovim calls in here: one command per source, and the help buffers that
-- are ours. :Rfc is the RFC Editor; :Eip is Ethereum's EIPs and ERCs, which
-- share one number space, so `:Eip 20` is ERC-20; :Bip is Bitcoin's BIPs;
-- :Simd is Solana's SIMDs; :W3c is the W3C's technical reports, which go
-- by shortname. Each takes a number (or shortname), a tag, `subjects` for
-- the source's taxonomy, words to search its index, or nothing for its
-- picker, and completes by number or title over what is cached. Nothing is
-- defined until the cds-lua on the runtimepath is seen to provide what the
-- plugin uses.

-- the one check kept here: a cds-lua-fp too old to carry cds.needs fails this
-- require, which is the answer
local ok, needs = pcall(require, "cds.needs")
local problem
if ok then
    problem = needs.check("rfc.nvim", require("rfc.needs"))
else
    problem = "rfc.nvim needs cds-lua-fp with cds.needs: install or update cds-io/cds-lua-fp"
end
if problem then
    vim.notify(problem, vim.log.levels.ERROR)
    return
end

local function define(name, prefix, desc)
    vim.api.nvim_create_user_command(name, function(cmd)
        local run, _ = require("rfc").command(require("rfc.sources")[prefix])
        run(cmd)
    end, {
        nargs = "*",
        complete = function(arglead, cmdline)
            local _, complete = require("rfc").command(require("rfc.sources")[prefix])
            return complete(arglead, cmdline)
        end,
        desc = desc,
    })
end

define("Rfc", "rfc", "Open an RFC as help: a number, a tag, subjects, a search, or nothing for the index")
define("Eip", "eip", "Open an EIP or ERC as help: a number, a tag, subjects, a search, or nothing for the index")
define("Bip", "bip", "Open a BIP as help: a number, a tag, subjects, a search, or nothing for the index")
define("Simd", "simd", "Open a SIMD as help: a number, a tag, a search, or nothing for the index")
define("W3c", "w3c", "Open a W3C report as help: a shortname, a tag, subjects, a search, or nothing for the index")

vim.api.nvim_create_autocmd("FileType", {
    pattern = "help",
    group = vim.api.nvim_create_augroup("rfc", { clear = true }),
    callback = function(args)
        require("rfc").attach(args.buf)
    end,
})
