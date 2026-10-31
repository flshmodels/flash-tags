local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Rules = require("../src/Rules")
local Transaction = require("../src/Transaction")
local count = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    count += 1
    print("PASS " .. name)
end
local function rejects(callback)
    assert(not pcall(callback), "expected an error")
end
for _, name in ipairs(fs.readDir("src")) do
    if name:match("%.luau$") then luau.compile(fs.readFile("src/" .. name)) end
end

test("transaction commits one batch", function()
    local writes, commits = 0, 0
    local ok = Transaction.apply({ {}, {} }, {
        validate = function() return true end,
        write = function() writes += 1 end,
    }, {
        begin = function() return "recording" end,
        finish = function(id, commit) assert(id == "recording" and commit) commits += 1 end,
    })
    assert(ok and writes == 2 and commits == 1)
end)
test("empty, stale and uncheckable plans never begin a recording", function()
    local function forbidden() error("must not be called") end
    for _, mode in ipairs({ "empty", "stale", "throw" }) do
        local began = false
        local ok = Transaction.apply(if mode == "empty" then {} else { {} }, {
            validate = function() if mode == "throw" then error("deleted") end return false, "stale" end,
            write = forbidden,
        }, { begin = function() began = true return "id" end, finish = forbidden })
        assert(not ok and not began)
    end
end)
test("refused or failing undo recordings do not edit objects", function()
    for _, mode in ipairs({ "refuse", "throw" }) do
        local writes = 0
        local ok = Transaction.apply({ {} }, { validate = function() return true end, write = function() writes += 1 end }, {
            begin = function() if mode == "throw" then error("busy") end return nil end,
            finish = function() error("must not finish") end,
        })
        assert(not ok and writes == 0)
    end
end)
test("write failures cancel and restore the fake scene", function()
    local state, snapshot, cancelled = 0, 0, false
    local ok = Transaction.apply({ {}, {} }, {
        validate = function() return true end,
        write = function() state += 1 if state == 2 then error("locked") end end,
    }, {
        begin = function() snapshot = state return "id" end,
        finish = function(_, commit) assert(not commit) state = snapshot cancelled = true end,
    })
    assert(not ok and cancelled and state == 0)
end)
test("failed commits attempt cancellation", function()
    local cancelled = false
    local ok = Transaction.apply({ {} }, { validate = function() return true end, write = function() end }, {
        begin = function() return "id" end,
        finish = function(_, commit) if commit then error("commit failed") end cancelled = true end,
    })
    assert(not ok and cancelled)
end)
test("failed cancellation is reported", function()
    local ok, message = Transaction.apply({ {} }, { validate = function() return true end, write = function() error("write failed") end }, {
        begin = function() return "id" end,
        finish = function() error("cancel failed") end,
    })
    assert(not ok and message:find("could not cancel", 1, true))
end)


local gameRoot = { Name = "Game", children = {} }
function gameRoot:IsA(class) return class == "DataModel" end
local function object(name, parent, class)
    local node = { Name = name, Parent = parent, ClassName = class or "Folder", children = {}, tags = {}, Locked = false, CollisionGroup = "Default" }
    function node:IsA(candidate)
        if candidate == self.ClassName then return true end
        if candidate == "BasePart" then return self.ClassName == "Part" end
        if candidate == "WorldRoot" then return self.ClassName == "WorldModel" or self.ClassName == "Workspace" end
        if candidate == "Model" then return self.ClassName == "WorldModel" or self.ClassName == "Workspace" end
        if candidate == "JointInstance" then return self.ClassName == "Weld" or self.ClassName == "Motor6D" end
        return false
    end
    function node:IsDescendantOf(ancestor)
        local cursor = self.Parent
        while cursor do if cursor == ancestor then return true end cursor = cursor.Parent end
        return false
    end
    function node:FindFirstAncestorWhichIsA(class)
        local cursor = self.Parent
        while cursor do if cursor:IsA(class) then return cursor end cursor = cursor.Parent end
        return nil
    end
    function node:GetChildren() return self.children end
    function node:GetFullName()
        local names, cursor = {}, self
        while cursor and cursor ~= gameRoot do table.insert(names, 1, cursor.Name) cursor = cursor.Parent end
        return table.concat(names, ".")
    end
    function node:HasTag(tag) return self.tags[tag] == true end
    function node:AddTag(tag) self.tags[tag] = true end
    function node:RemoveTag(tag) self.tags[tag] = nil end
    if parent then table.insert(parent.children, node) end
    return node
end
local world = object("Workspace", gameRoot, "Workspace")
local groups = { Default = true, Scenery = true }
local function readGroups()
    local result = {}
    for name in pairs(groups) do table.insert(result, { name = name, mask = 0 }) end
    return result
end
function world:GetRegisteredCollisionGroups() return readGroups() end
function gameRoot:GetService(name)
    assert(name == "PhysicsService")
    return { GetRegisteredCollisionGroups = readGroups }
end
local Scope = luau.load(fs.readFile("src/Scope.luau"), { environment = { game = gameRoot } })()
local modules = { Rules = Rules, Scope = Scope }
local Adapter = luau.load(fs.readFile("src/Adapter.luau"), { environment = {
    require = function(name) assert(modules[name]) return modules[name] end,
    script = { Parent = { Rules = "Rules", Scope = "Scope" } }, game = gameRoot, workspace = world,
} })()

test("scope deduplicates overlapping roots", function()
    local folder = object("Folder", world)
    local a, b = object("A", folder), object("B", folder)
    local targets, scanned = Scope.collect({ folder, a }, true, function() return true end)
    assert(#targets == 3 and scanned == 3 and targets[1] == folder and targets[2] == b and targets[3] == a)
    local only = Scope.collect({ folder }, false, function() return true end)
    assert(#only == 1)
end)
test("scope rejects detached roots, services and empty selections", function()
    rejects(function() Scope.collect({}, true, function() return true end) end)
    rejects(function() Scope.collect({ world }, true, function() return true end) end)
    rejects(function() Scope.collect({ object("Detached", nil) }, true, function() return true end) end)
end)
test("scope limits discovered objects before returning partial results", function()
    local folder = object("Folder", world)
    object("A", folder) object("B", folder)
    rejects(function() Scope.collect({ folder }, true, function() return false end, { maxNodes = 2, maxTargets = 2 }) end)
end)
test("scope target limit is independent of scan limit", function()
    local folder = object("Folder", world)
    object("A", folder) object("B", folder)
    rejects(function() Scope.collect({ folder }, true, function() return true end, { maxNodes = 10, maxTargets = 2 }) end)
end)

test("Add skips existing tags and preserves unrelated tags", function()
    local a, b = object("A", world), object("B", world)
    a:AddTag("Other") b:AddTag("Interactable")
    local plan = Adapter.plan({ a, b }, { tag = "Interactable", mode = "Add", expand = false })
    assert(#plan == 1 and not a:HasTag("Interactable"))
    Adapter.write(plan[1])
    assert(a:HasTag("Interactable") and a:HasTag("Other"))
end)
test("Remove skips absent tags", function()
    local a, b = object("A", world), object("B", world)
    a:AddTag("Old")
    local plan = Adapter.plan({ a, b }, { tag = "Old", mode = "Remove", expand = false })
    assert(#plan == 1) Adapter.write(plan[1])
    assert(not a:HasTag("Old"))
end)
test("Replace preserves an existing destination tag", function()
    local a, b = object("A", world), object("B", world)
    a:AddTag("Old") a:AddTag("New") a:AddTag("Other")
    local plan = Adapter.plan({ a, b }, { tag = "Old", replacement = "New", mode = "Replace", expand = false })
    assert(#plan == 1 and Adapter.validate(plan)) Adapter.write(plan[1])
    assert(a:HasTag("New") and a:HasTag("Other") and not a:HasTag("Old") and not b:HasTag("New"))
end)
test("tag changes and replacement changes invalidate previews", function()
    local a = object("A", world) a:AddTag("Old")
    local plan = Adapter.plan({ a }, { tag = "Old", replacement = "New", mode = "Replace", expand = false })
    a:AddTag("New") assert(not Adapter.validate(plan))
    a:RemoveTag("New") a:RemoveTag("Old") assert(not Adapter.validate(plan))
end)
test("tag names and replace operations are validated", function()
    for _, tag in ipairs({ "", "a b", "a@b", string.rep("x", 65) }) do rejects(function() Rules.checkTag(tag) end) end
    rejects(function() Adapter.plan({ object("A", world) }, { tag = "Same", replacement = "Same", mode = "Replace" }) end)
    rejects(function() Rules.plan({ {} }, { tag = "Valid", mode = "Unknown" }) end)
end)
test("nested tag scopes deduplicate roots", function()
    local folder = object("Folder", world)
    local a = object("A", folder)
    local plan = Adapter.plan({ folder, a }, { tag = "Tag", mode = "Add", expand = true })
    assert(#plan == 2)
end)
test("reparented targets block tag changes", function()
    local a = object("A", world)
    local plan = Adapter.plan({ a }, { tag = "Tag", mode = "Add", expand = false })
    a.Parent = nil assert(not Adapter.validate(plan))
end)

print(string.format("%d checks passed", count))
