-- CraftQueue.lua: saved profession crafts, their prerequisites, missing materials, and ordered execution.
local ns = _G.NaowhForever

local P = ns.Professions
local C = P.C
local R = P.Recipes
local W = P.State
local Shopping = P.Shopping
local V = P.Vendors

local MAX_DEPTH = 4
local QUEUE_DELAY = C.QUEUE_DELAY or 0.2
local TEXT_UNKNOWN = "?"
local TEXT_NOTHING = ns.L("Nothing in the crafting queue can be crafted with the materials in your bags.")
local EMPTY = {}

local Queue = {}
P.CraftQueue = Queue

local running, active
local runID = 0
local skipped = {}
local events = CreateFrame("Frame")
local SyncShopping

local function Mine()
    local account = ns.AccountSettings()
    if type(account.profCraftQueue) ~= "table" then account.profCraftQueue = {} end
    local key = (UnitName("player") or TEXT_UNKNOWN) .. "-" .. (GetRealmName() or TEXT_UNKNOWN)
    local mine = account.profCraftQueue[key]
    if type(mine) ~= "table" then
        mine = { prerequisites = {}, crafts = {} }
        account.profCraftQueue[key] = mine
    end
    if type(mine.prerequisites) ~= "table" then mine.prerequisites = {} end
    if type(mine.crafts) ~= "table" then mine.crafts = {} end
    return mine
end

local function Redraw()
    if Queue.Render then Queue.Render() end
end

local function CopyNeed(recipeID)
    local need = {}
    local ok, reagents = pcall(R.Reagents, recipeID)
    for _, reagent in ipairs(ok and reagents or EMPTY) do
        if reagent.itemID then need[reagent.itemID] = reagent.need or 1 end
    end
    return need
end

local function RecipeData(recipeID, fallback)
    local okInfo, info = pcall(C_TradeSkillUI.GetRecipeInfo, recipeID)
    if not okInfo then info = nil end
    local output, made = R.OutputItem(recipeID)
    local known = Shopping.Makes()[output or 0]
    local need = CopyNeed(recipeID)
    return {
        recipeID = recipeID,
        name = (info and info.name) or (fallback and fallback.name) or (C_Spell.GetSpellName and C_Spell.GetSpellName(recipeID))
            or ("Recipe " .. recipeID),
        icon = (info and info.icon) or (fallback and fallback.icon) or C_Spell.GetSpellTexture(recipeID),
        need = next(need) and need or (fallback and fallback.need) or {},
        output = output,
        made = made or (known and known.made) or 1,
        prof = known and known.prof,
    }
end

local function AddEntry(bucket, recipeID, count, fallback)
    count = math.max(1, math.min(C.MAX_CRAFTS, tonumber(count) or 1))
    local entry = bucket[recipeID]
    if entry then
        entry.count = math.min(C.MAX_CRAFTS, (tonumber(entry.count) or 0) + count)
        return entry
    end
    entry = RecipeData(recipeID, fallback)
    entry.count = count
    bucket[recipeID] = entry
    return entry
end

local function RequirementPlan(recipeID, count, bucket, inventory, visiting, depth)
    if depth >= MAX_DEPTH or visiting[recipeID] then return end
    visiting[recipeID] = true
    for _, reagent in ipairs(R.Reagents(recipeID) or EMPTY) do
        local want = (reagent.need or 1) * count
        if inventory[reagent.itemID] == nil then inventory[reagent.itemID] = R.ItemCount(reagent.itemID) end
        local have = math.min(want, inventory[reagent.itemID] or 0)
        inventory[reagent.itemID] = (inventory[reagent.itemID] or 0) - have
        local missing = want - have
        local make = Shopping.Makes()[reagent.itemID]
        if missing > 0 and make and not make.cooldown then
            local plan = { cost = {}, make = {}, craft = {}, busy = {}, owned = R.Owned() }
            local _, cheaper = Shopping.Cheapest(reagent.itemID, plan, 0)
            if cheaper then
                local crafts = math.ceil(missing / math.max(1, make.made or 1))
                RequirementPlan(make.recipe, crafts, bucket, inventory, visiting, depth + 1)
                AddEntry(bucket, make.recipe, crafts, { need = make.need, made = make.made })
                inventory[reagent.itemID] = (inventory[reagent.itemID] or 0) + crafts * (make.made or 1) - missing
            end
        end
    end
    visiting[recipeID] = nil
end

local function Add(info, count, prerequisite, defer)
    if not (info and info.recipeID) then return end
    local mine = Mine()
    count = math.max(1, math.min(C.MAX_CRAFTS, tonumber(count) or 1))
    if not prerequisite then
        local inventory = {}
        for _, reagent in ipairs(R.Reagents(info.recipeID) or EMPTY) do
            inventory[reagent.itemID] = R.ItemCount(reagent.itemID)
        end
        RequirementPlan(info.recipeID, count, mine.prerequisites, inventory, {}, 0)
    end
    AddEntry(prerequisite and mine.prerequisites or mine.crafts, info.recipeID, count, info)
    if not defer then Redraw() end
end

local function Bucket(prerequisite)
    local mine = Mine()
    return prerequisite and mine.prerequisites or mine.crafts
end

local function Step(recipeID, prerequisite, by)
    local bucket = Bucket(prerequisite)
    local entry = bucket[recipeID]
    if not entry then return end
    entry.count = math.max(1, math.min(C.MAX_CRAFTS, (tonumber(entry.count) or 1) + by))
    SyncShopping()
end

local function Remove(recipeID, prerequisite)
    Bucket(prerequisite)[recipeID] = nil
    if active and active.recipeID == recipeID and active.prerequisite == prerequisite then
        running, active = nil, nil
        runID = runID + 1
        events:UnregisterAllEvents()
    end
    SyncShopping()
end

local function Requirements(entry)
    local rows, missing, missingVendor, vendorCost = {}, false, false, 0
    for itemID, per in pairs(entry.need or EMPTY) do
        local need = per * (tonumber(entry.count) or 1)
        local have = R.ItemCount(itemID)
        local short = math.max(0, need - have)
        local vendor = V.IsVendorItem(itemID) and true or false
        local price = vendor and V.Prices()[itemID]
        if short > 0 then
            missing = true
            if vendor then missingVendor = true end
            if price then vendorCost = vendorCost + price * short end
        end
        rows[#rows + 1] = { itemID = itemID, name = R.ItemName(itemID) or ("Item " .. itemID),
            need = need, have = have, missing = short, vendor = vendor, vendorPrice = price }
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return rows, missing, missingVendor, vendorCost
end

local function CanCraft(entry)
    local _, missing = Requirements(entry)
    if missing then return false end
    local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, entry.recipeID)
    if not ok then return false end
    if not (info and info.learned ~= false) then return false end
    local okCooldown, cooldown = pcall(C_TradeSkillUI.GetRecipeCooldown, entry.recipeID)
    if okCooldown and cooldown and cooldown > 0 then return false end
    local okRequirements, requirements = pcall(C_TradeSkillUI.GetRecipeRequirements, entry.recipeID)
    if okRequirements and requirements then
        for _, requirement in ipairs(requirements) do
            if requirement.met == false then return false end
        end
    end
    return true
end

local function Ordered()
    local mine, out = Mine(), {}
    for _, prerequisite in ipairs({ true, false }) do
        for _, entry in pairs(prerequisite and mine.prerequisites or mine.crafts) do
            entry.prerequisite = prerequisite
            out[#out + 1] = entry
        end
    end
    table.sort(out, function(a, b)
        if a.prerequisite ~= b.prerequisite then return a.prerequisite end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

local function FinishActive()
    if not active then return end
    local bucket = Bucket(active.prerequisite)
    local entry = bucket[active.recipeID]
    if entry then
        entry.count = (tonumber(entry.count) or 1) - 1
        if entry.count <= 0 then bucket[active.recipeID] = nil end
    end
    active.done = active.done + 1
    Redraw()
end

local function Stop()
    running, active = nil, nil
    runID = runID + 1
    events:UnregisterAllEvents()
    Redraw()
end

local PrepareNext

local function Continue()
    if not running then return end
    local expectedRun = runID
    active = nil
    C_Timer.After(QUEUE_DELAY, function()
        if running and runID == expectedRun then PrepareNext() end
    end)
end

local function OnCraftEvent(_, event, unit, _, spellID)
    if not (running and active) then return end
    if event == "BAG_UPDATE_DELAYED" then return Redraw() end
    if not active.started then return end
    if unit ~= "player" or spellID ~= active.recipeID then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        FinishActive()
        if active.done >= active.requested then Continue() end
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        Stop()
    end
end

local function SelectForCrafting(entry)
    W.selectedID, W.selectedUnlearned = entry.recipeID, nil
    if P.List and P.List.Render then P.List.Render() end
    if P.Detail and P.Detail.Render then P.Detail.Render() end
    local frame = W.frame
    if frame and frame.qty then frame.qty:SetText(tostring(entry.count)) end
end

function PrepareNext()
    if not running then return end
    local entries = Ordered()
    if #entries == 0 then return Stop() end
    local chosen
    for _, entry in ipairs(entries) do
        if CanCraft(entry) then chosen = entry break end
    end
    if not chosen then
        Stop()
        return ns.Print(TEXT_NOTHING)
    end
    local count = tonumber(chosen.count) or 1
    active = { recipeID = chosen.recipeID, prerequisite = chosen.prerequisite,
        requested = count, done = 0, started = false }
    SelectForCrafting(chosen)
    Redraw()
end

local function OnCraftRequested(recipeID, count)
    if not (running and active and recipeID == active.recipeID) then return end
    local entry = Bucket(active.prerequisite)[active.recipeID]
    if not entry then return Stop() end
    active.requested = math.min(tonumber(count) or 1, tonumber(entry.count) or 1)
    active.done, active.started = 0, true
    Redraw()
end

local function Start()
    if running then return end
    runID = runID + 1
    running = true
    events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    Redraw()
    PrepareNext()
end

local function Click()
    if InCombatLockdown and InCombatLockdown() then return end
    if not running then
        Start()
        return
    end
    if not (active and not active.started) then return end
    local selected = R.SelectedInfo()
    if not (selected and selected.recipeID == active.recipeID) then
        local entry = Bucket(active.prerequisite)[active.recipeID]
        if not entry then return Stop() end
        SelectForCrafting(entry)
        return
    end
    -- This is intentionally called only from the Craft Next button's physical
    -- click.  It is the same hardware-event craft path used by Naowh's Create
    -- button; queue progression itself never invokes a protected craft action.
    R.Craft(active.requested)
end

local function MarkSkipped(itemID, qty)
    skipped[itemID] = (skipped[itemID] or 0) + (qty or 0)
end

local function ResetSkipped()
    wipe(skipped)
end

local function ImportShopping()
    local available = {}
    for itemID, qty in pairs(Shopping.Have()) do
        available[itemID] = math.max(0, qty - (skipped[itemID] or 0))
    end
    local promoted, list, mine = false, Shopping.List(), Mine()
    local ordered = {}
    for recipeID, craft in pairs(list) do
        ordered[#ordered + 1] = { recipeID = recipeID, craft = craft }
    end
    table.sort(ordered, function(a, b) return (a.craft.name or "") < (b.craft.name or "") end)

    local function Expand(itemID, qty, leaves, prerequisites, visiting, depth)
        if qty <= 0 then return end
        local make = Shopping.Makes()[itemID]
        local cheaper = false
        if make and not make.cooldown and depth < MAX_DEPTH and not visiting[itemID] then
            local plan = { cost = {}, make = {}, craft = {}, busy = {}, owned = R.Owned() }
            cheaper = select(2, Shopping.Cheapest(itemID, plan, 0)) and true or false
        end
        if not cheaper then
            leaves[itemID] = (leaves[itemID] or 0) + qty
            return
        end
        visiting[itemID] = true
        local crafts = math.ceil(qty / math.max(1, make.made or 1))
        prerequisites[make.recipe] = (prerequisites[make.recipe] or 0) + crafts
        local owned = R.Owned()
        for part, per in pairs(make.need or EMPTY) do
            if not owned[part] and Shopping.ShouldBuyAH(part) then
                Expand(part, per * crafts, leaves, prerequisites, visiting, depth + 1)
            end
        end
        visiting[itemID] = nil
    end

    for _, candidate in ipairs(ordered) do
        local craft, leaves, prerequisites = candidate.craft, {}, {}
        for itemID, per in pairs(craft.need or EMPTY) do
            local qty = per * craft.count - (craft.got and craft.got[itemID] or 0)
            Expand(itemID, qty, leaves, prerequisites, {}, 0)
        end
        local ready = true
        for itemID, qty in pairs(leaves) do
            if (available[itemID] or 0) < qty then ready = false break end
        end
        if ready then
            for itemID, qty in pairs(leaves) do
                available[itemID] = available[itemID] - qty
                local have = Shopping.Have()
                have[itemID] = math.max(0, (have[itemID] or 0) - qty)
                if have[itemID] == 0 then have[itemID] = nil end
            end
            if not craft.fromQueue then
                for recipeID, count in pairs(prerequisites) do
                    local output
                    for itemID, make in pairs(Shopping.Makes()) do
                        if make.recipe == recipeID then output = itemID break end
                    end
                    local make = output and Shopping.Makes()[output]
                    AddEntry(mine.prerequisites, recipeID, count, make and { need = make.need, made = make.made })
                end
                AddEntry(mine.crafts, candidate.recipeID, craft.count, craft)
            end
            list[candidate.recipeID] = nil
            promoted = true
        end
    end
    if not promoted then return false end
    Shopping.Trim()
    Redraw()
    Shopping.Redraw()
    return true
end

local function OnPurchased()
    return ImportShopping()
end

SyncShopping = function()
    local mine, list = Mine(), Shopping.List()
    local legacyCounts = {}
    for recipeID, craft in pairs(list) do
        if craft.fromQueue or mine.crafts[recipeID] then
            if not craft.fromQueue then legacyCounts[recipeID] = tonumber(craft.count) or 0 end
            list[recipeID] = nil
        end
    end

    local entries = {}
    for _, entry in pairs(mine.crafts) do entries[#entries + 1] = entry end
    table.sort(entries, function(a, b) return (a.name or "") < (b.name or "") end)

    local inventory = {}
    local purchased = Shopping.Have()
    for _, entry in ipairs(entries) do
        for itemID in pairs(entry.need or EMPTY) do
            if inventory[itemID] == nil then
                inventory[itemID] = math.max(0, R.ItemCount(itemID) - (purchased[itemID] or 0))
            end
        end
    end
    for _, entry in ipairs(entries) do
        local count = math.max(tonumber(entry.count) or 1, legacyCounts[entry.recipeID] or 0)
        local got = {}
        for itemID, per in pairs(entry.need or EMPTY) do
            local want = per * count
            local have = math.min(want, inventory[itemID] or 0)
            inventory[itemID] = (inventory[itemID] or 0) - have
            if have > 0 then got[itemID] = have end
        end
        local info = { recipeID = entry.recipeID, name = entry.name, icon = entry.icon }
        Shopping.Add(info, count, next(got) and got or nil, true, true, true)
    end
    Shopping.Trim()
    Redraw()
    Shopping.Redraw()
end

local function AddWithShopping(info, count)
    Add(info, count, nil, true)
    SyncShopping()
end

events:SetScript("OnEvent", OnCraftEvent)
if hooksecurefunc then hooksecurefunc(C_TradeSkillUI, "CraftRecipe", OnCraftRequested) end

Queue.List = Mine
Queue.Add = Add
Queue.AddWithShopping = AddWithShopping
Queue.Step = Step
Queue.Remove = Remove
Queue.Requirements = Requirements
Queue.Ordered = Ordered
Queue.Click = Click
Queue.Running = function() return running and true or false end
Queue.Active = function() return active end
Queue.MarkSkipped = MarkSkipped
Queue.ResetSkipped = ResetSkipped
Queue.OnPurchased = OnPurchased
