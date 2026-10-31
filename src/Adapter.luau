local Rules = require(script.Parent.Rules)
local Scope = require(script.Parent.Scope)
local Adapter = {}

function Adapter.controls(panel, changed)
    panel.label("Add, remove or replace one tag. Replace only affects objects that already have the old tag; other tags stay as they are.")
    local mode = panel.cycle("Operation", { "Add", "Remove", "Replace" }, changed)
    local tag = panel.field("Tag / old tag", "Interactable")
    local replacement = panel.field("Replacement tag (Replace only)", "")
    local expand = panel.cycle("Scope", { "Selection only", "Include descendants" }, changed)
    tag:GetPropertyChangedSignal("Text"):Connect(changed)
    replacement:GetPropertyChangedSignal("Text"):Connect(changed)
    return function() return { mode = mode(), tag = tag.Text, replacement = replacement.Text, expand = expand() == "Include descendants" } end
end

function Adapter.plan(selection, options)
    Rules.checkTag(options.tag)
    if options.mode == "Replace" then Rules.checkTag(options.replacement) end
    local objects, scanned = Scope.collect(selection, options.expand, function() return true end)
    local rows = {}
    for _, object in ipairs(objects) do
        table.insert(rows, {
            target = object, parent = object.Parent, hasTag = object:HasTag(options.tag),
            hasReplacement = options.mode == "Replace" and object:HasTag(options.replacement) or false,
        })
    end
    local plan = Rules.plan(rows, options)
    plan.summary = string.format("%d changes / %d objects scanned.", #plan, scanned)
    for _, entry in ipairs(plan) do
        entry.label = entry.before.target:GetFullName() .. "\n" .. entry.mode .. " " .. entry.tag
        if entry.mode == "Replace" then entry.label ..= " -> " .. entry.replacement end
    end
    return plan
end

function Adapter.validate(plan)
    for _, entry in ipairs(plan) do
        local before = entry.before
        if not before.target:IsDescendantOf(game) or before.target.Parent ~= before.parent
            or before.target:HasTag(entry.tag) ~= before.hasTag then
            return false, "A target or its tag changed. Preview again."
        end
        if entry.mode == "Replace" and before.target:HasTag(entry.replacement) ~= before.hasReplacement then
            return false, "A replacement tag changed. Preview again."
        end
    end
    return true
end

function Adapter.write(entry)
    local object = entry.before.target
    if entry.mode == "Add" then
        object:AddTag(entry.tag)
    elseif entry.mode == "Remove" then
        object:RemoveTag(entry.tag)
    else
        object:AddTag(entry.replacement)
        object:RemoveTag(entry.tag)
    end
end

return Adapter
