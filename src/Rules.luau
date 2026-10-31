local Rules = {}

function Rules.checkTag(tag)
    assert(type(tag) == "string" and #tag > 0 and #tag <= 64 and tag:match("^[A-Za-z0-9_.-]+$"), "Tags must contain 1-64 ASCII letters, digits, underscores, periods or hyphens.")
end

function Rules.plan(rows, options)
    assert(#rows > 0 and #rows <= 1000, "Choose between 1 and 1000 objects.")
    Rules.checkTag(options.tag)
    assert(options.mode == "Add" or options.mode == "Remove" or options.mode == "Replace", "Choose Add, Remove or Replace.")
    if options.mode == "Replace" then
        Rules.checkTag(options.replacement)
        assert(options.replacement ~= options.tag, "Replacement must differ from the old tag.")
    end
    local plan = {}
    for _, row in ipairs(rows) do
        local changed = if options.mode == "Add" then not row.hasTag else row.hasTag
        if changed then
            table.insert(plan, { before = row, tag = options.tag, replacement = options.replacement, mode = options.mode })
        end
    end
    return plan
end

return Rules
