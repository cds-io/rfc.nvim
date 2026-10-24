-- The plugin's own lazy.nvim spec, read from this file by lazy's pkg source
-- and merged into whatever spec the reader wrote. Eager, since setup() puts
-- the document store on the runtimepath so `:help rfc9110` works in a fresh
-- session; `main` is the module opts go to. The house library is a
-- dependency tracking its main, loaded on its first require, so
-- `require("cds.fp")` resolves to one copy on the runtimepath however many
-- plugins of the family are installed.
return {
    "cds-io/rfc.nvim",
    lazy = false,
    main = "rfc",
    dependencies = {
        { "cds-io/cds-lua", lazy = true },
    },
}
