-- Type check: `nvim -l scripts/typecheck.lua`. Runs lua-language-server's
-- --check over lua/ and plugin/ with Neovim's own runtime types and the house
-- library in the library. The runtime path is the one only Neovim knows
-- (vim.env.VIMRUNTIME), so the configuration is written here rather than
-- committed. The exit code is the server's: 1 when anything at Warning or
-- above is found.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
-- the checkout beside this one, where .busted and CI put it
local cds = vim.fn.fnamemodify(root .. "/../cds-lua/lua", ":p")
if vim.fn.isdirectory(cds) == 0 then
    io.stderr:write("cds-lua is not checked out beside this plugin: " .. cds .. "\n")
    os.exit(1)
end
local config = vim.fn.tempname() .. ".luarc.json"
vim.fn.writefile({
    vim.json.encode({
        ["runtime.version"] = "LuaJIT",
        -- require("rfc") is lua/rfc/init.lua alone; the loose default also
        -- matches plugin/rfc.lua by its name, and every field of the module
        -- is undefined on that one
        ["runtime.pathStrict"] = true,
        ["runtime.path"] = { "lua/?.lua", "lua/?/init.lua" },
        ["workspace.library"] = { vim.env.VIMRUNTIME .. "/lua", "${3rd}/luv/library", cds },
        ["workspace.ignoreDir"] = { "spec", "doc", ".git" },
        ["workspace.checkThirdParty"] = false,
        ["diagnostics.globals"] = { "vim", "MiniDoc" },
    }),
}, config)
local server = vim.env.LUALS or "lua-language-server"
local result = vim.system({ server, "--check", root, "--configpath", config, "--checklevel", "Warning" }):wait()
io.stdout:write(result.stdout or "")
io.stderr:write(result.stderr or "")
os.exit(result.code)
