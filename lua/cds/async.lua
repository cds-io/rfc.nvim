-- The one module that names vim.async. It is new in Neovim 0.13 and may still
-- change before that release; every caller goes through here, so a rename
-- is a one-file fix.
assert(vim.async, "requires Neovim 0.13+ (vim.async)")

return vim.async
