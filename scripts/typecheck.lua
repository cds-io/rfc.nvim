-- Type check: `nvim -l scripts/typecheck.lua`. Runs lua-language-server's
-- --check over lua/ and plugin/ with Neovim's own runtime types and the house
-- library in the library. The runtime path is the one only Neovim knows
-- (vim.env.VIMRUNTIME), so the configuration is written here rather than
-- committed. The exit code is the server's: 1 when anything at Warning or
-- above is found.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
-- the checkouts beside this one, where .busted and CI put them
local cds = vim.fn.fnamemodify(root .. "/../cds-lua/lua", ":p")
local rock = vim.fn.fnamemodify(root .. "/../cds-lua-fp/lua", ":p")
for _, dir in ipairs({ cds, rock }) do
    if vim.fn.isdirectory(dir) == 0 then
        io.stderr:write("not checked out beside this plugin: " .. dir .. "\n")
        os.exit(1)
    end
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
        ["workspace.library"] = { vim.env.VIMRUNTIME .. "/lua", "${3rd}/luv/library", cds, rock },
        ["workspace.ignoreDir"] = { "spec", "doc", ".git" },
        ["workspace.checkThirdParty"] = false,
        ["diagnostics.globals"] = { "vim", "MiniDoc" },
    }),
}, config)
-- The binary: LUALS when set, else the first of PATH and Mason's install
-- (Neovim's data directory, where :MasonInstall puts it) that has one.
local function find_server()
    local mason = vim.fn.stdpath("data") .. "/mason/bin/lua-language-server"
    for _, candidate in ipairs({ vim.env.LUALS or "", vim.fn.exepath("lua-language-server"), mason }) do
        if candidate ~= "" and vim.fn.executable(candidate) == 1 then
            return candidate
        end
    end
    io.stderr:write(
        "no lua-language-server: LUALS is "
            .. (vim.env.LUALS or "unset")
            .. ", PATH has none, and Mason's "
            .. mason
            .. " is not there\n"
    )
    os.exit(1)
end
local server = find_server()
local result = vim.system({ server, "--check", root, "--configpath", config, "--checklevel", "Warning" }):wait()
io.stdout:write(result.stdout or "")
io.stderr:write(result.stderr or "")
os.exit(result.code)
