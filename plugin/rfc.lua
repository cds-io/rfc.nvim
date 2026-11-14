-- Neovim calls in here: the shipped sources registered, one command per
-- registered source, and the help buffers that are ours. :Rfc is the RFC
-- Editor; :Eip is Ethereum's EIPs and ERCs, which share one number space, so
-- `:Eip 20` is ERC-20; :Bip is Bitcoin's BIPs; :Simd is Solana's SIMDs; :W3c
-- is the W3C's technical reports and :Crs the Congressional Research
-- Service's reports, both by shortname. Each takes a number (or shortname), a
-- tag, `subjects` for the source's taxonomy, words to search its index, or
-- nothing for its picker, and completes by number or title over what is
-- cached. Nothing is defined until the cds-lua on the runtimepath is seen to
-- provide what the plugin uses.

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

-- The sources the plugin ships, registered in the order a picker lists them.
-- A spec is the source's identity and command; its record loads the first
-- time the source is used.
local SHIPPED = {
    {
        prefix = "rfc",
        label = "RFC",
        command = "Rfc",
        default_on = true,
        module = "rfc.sources.rfc",
        desc = "Open an RFC as help: a number, a tag, subjects, a search, or nothing for the index; ! cc clears its cache",
    },
    {
        prefix = "eip",
        aliases = { "erc" },
        label = "EIP",
        command = "Eip",
        module = "rfc.sources.eip",
        desc = "Open an EIP or ERC as help: a number, a tag, subjects, a search, or nothing for the index; ! cc clears its cache",
    },
    {
        prefix = "bip",
        label = "BIP",
        command = "Bip",
        module = "rfc.sources.bip",
        desc = "Open a BIP as help: a number, a tag, subjects, a search, or nothing for the index; ! cc clears its cache",
    },
    {
        prefix = "simd",
        label = "SIMD",
        command = "Simd",
        module = "rfc.sources.simd",
        desc = "Open a SIMD as help: a number, a tag, a search, or nothing for the index; ! cc clears its cache",
    },
    {
        prefix = "w3c",
        key = "shortname",
        label = "W3C",
        command = "W3c",
        module = "rfc.sources.w3c",
        desc = "Open a W3C report as help: a shortname, a tag, subjects, a search, or nothing for the index; ! cc clears its cache",
    },
    {
        prefix = "crs",
        key = "shortname",
        label = "CRS",
        command = "Crs",
        module = "rfc.sources.crs",
        desc = "Open a CRS report as help: a number, a tag, subjects, a search, or nothing for the index; ! cc clears its cache",
    },
}

local sources = require("rfc.sources")
for _, spec in ipairs(SHIPPED) do
    local registered, err = sources.register(spec)
    if not registered then
        vim.notify("rfc.nvim: " .. err, vim.log.levels.ERROR)
    end
end

for _, spec in ipairs(sources.specs()) do
    local prefix = spec.prefix
    require("cds.command").register({
        {
            name = spec.command,
            run = function(cmd)
                local run, _ = require("rfc").command(assert(sources.get(prefix)))
                run(cmd)
            end,
            nargs = "*",
            bang = true,
            complete = function(arglead, cmdline)
                local _, complete = require("rfc").command(assert(sources.get(prefix)))
                return complete(arglead, cmdline)
            end,
            desc = spec.desc,
            notify = function(message, level)
                require("rfc").notify(message, level)
            end,
        },
    })
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "help",
    group = vim.api.nvim_create_augroup("rfc", { clear = true }),
    callback = function(args)
        require("rfc").attach(args.buf)
    end,
})

-- Shared document buffers keep plugin-owned source resolution and mappings.
local documents = vim.api.nvim_create_augroup("rfc.documents", { clear = true })
vim.api.nvim_create_autocmd("BufReadCmd", {
    group = documents,
    pattern = "rfc://document/*",
    callback = function(args)
        require("rfc").read_document(args.buf, vim.api.nvim_buf_get_name(args.buf))
    end,
})
vim.api.nvim_create_autocmd("BufWinEnter", {
    group = documents,
    pattern = "rfc://document/*",
    callback = function()
        require("rfc").document_window(vim.api.nvim_get_current_win())
    end,
})
vim.api.nvim_create_autocmd("WinClosed", {
    group = documents,
    callback = function(args)
        require("rfc").document_forget(tonumber(args.match))
    end,
})
vim.api.nvim_create_autocmd("ColorScheme", {
    group = documents,
    callback = function()
        require("cds.vellum").restyle()
    end,
})
