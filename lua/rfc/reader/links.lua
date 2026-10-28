-- Follow application tags, local fragments and external URLs.
return function(model_of, navigate, jump, notify, cancel)
    return function(target)
        local tag = target:match("^rfc%-tag:(.+)$")
        if tag then
            navigate(tag)
            return
        end
        local model = model_of(vim.api.nvim_get_current_buf())
        local base, fragment = target:match("^([^#]*)#(.*)$")
        if fragment and (base == "" or model and base == model.document.url) then
            if not jump(vim.api.nvim_get_current_win(), fragment, true) then
                notify("no anchor: " .. fragment)
            end
            return
        end
        local report = target:match("^https?://www%.w3%.org/TR/([^/#?]+)/?")
        if report then
            navigate("w3c-" .. report:lower() .. (fragment and "#" .. fragment or ""))
            return
        end
        local crs = target:lower():match("^https?://www%.everycrsreport%.com/reports/([^/#?]+)%.html")
        if crs then
            navigate("crs-" .. crs .. (fragment and "#" .. fragment or ""))
            return
        end
        cancel(vim.api.nvim_get_current_win())
        local scheme = (target:match("^(%a[%w+.-]*):") or ""):lower()
        if scheme == "javascript" or scheme == "data" then
            notify("not followed: " .. target)
            return
        end
        vim.ui.open(target)
    end
end
