-- Crafting queue regression coverage: prerequisites, vendor shortages, and ordered execution.
local frames = {}
local inventory = { [2000] = 0, [3000] = 0, [4000] = 0, [5000] = 0 }
local crafts = {}
local account = {}
local shoppingList, shoppingHave = {}, {}
local ahCheaper = {}
local selected, quantity
local craftHook

function wipe(t) for key in pairs(t) do t[key] = nil end return t end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function hooksecurefunc(_, name, fn) if name == "CraftRecipe" then craftHook = fn end end
function CreateFrame()
    local frame = {}
    function frame:SetScript(_, fn) self.onEvent = fn end
    function frame:RegisterUnitEvent() end
    function frame:RegisterEvent() end
    function frame:UnregisterAllEvents() end
    frames[#frames + 1] = frame
    return frame
end

C_Timer = { After = function(_, fn) fn() end }
C_Item = {}
C_Spell = {
    GetSpellName = function(id) return "Recipe " .. id end,
    GetSpellTexture = function(id) return id end,
}
C_TradeSkillUI = {
    GetRecipeInfo = function(id)
        return { recipeID = id, name = id == 100 and "Main Craft" or "Prerequisite", icon = id, learned = true }
    end,
    GetRecipeCooldown = function() return nil end,
    GetRecipeRequirements = function() return {} end,
    CraftRecipe = function(id, count)
        crafts[#crafts + 1] = { id = id, count = count }
        if craftHook then craftHook(id, count) end
    end,
}

local makes = {
    [1000] = { recipe = 100, made = 1, need = { [2000] = 1, [3000] = 2, [4000] = 1 } },
    [2000] = { recipe = 200, made = 1, need = { [5000] = 2 } },
}
local reagents = {
    [100] = { { itemID = 2000, need = 1 }, { itemID = 3000, need = 2 }, { itemID = 4000, need = 1 } },
    [200] = { { itemID = 5000, need = 2 } },
}

local ns = {
    L = function(text) return text end,
    Print = function() end,
    AccountSettings = function() return account end,
    Professions = {
        C = { MAX_CRAFTS = 999, QUEUE_DELAY = 0 },
        State = { frame = { qty = { SetText = function(_, value) quantity = value end } } },
        List = { Render = function() end },
        Detail = { Render = function() end },
        Recipes = {
            Reagents = function(id) return reagents[id] or {} end,
            OutputItem = function(id) return id == 100 and 1000 or 2000, 1 end,
            ItemCount = function(id) return inventory[id] or 0 end,
            ItemName = function(id) return "Item " .. id end,
            Owned = function() return {} end,
            SelectedInfo = function()
                local root = _G.NaowhForever
                local id = root and root.Professions.State.selectedID
                return id and C_TradeSkillUI.GetRecipeInfo(id)
            end,
            Craft = function(count)
                local id = _G.NaowhForever.Professions.State.selectedID
                if id then C_TradeSkillUI.CraftRecipe(id, count) end
            end,
        },
        Shopping = {
            Makes = function() return makes end,
            Cheapest = function(item) return item == 2000 and 40 or 20, item == 2000 end,
            List = function() return shoppingList end,
            Have = function() return shoppingHave end,
            Materials = function() return {}, {} end,
            Trim = function() end,
            Redraw = function() end,
            Add = function() end,
            ShouldBuyAH = function(id) return ahCheaper[id] or id ~= 4000 end,
        },
        Vendors = {
            IsVendorItem = function(id) return id == 4000 end,
            Prices = function() return { [4000] = 25 } end,
        },
    },
}
_G.NaowhForever = ns

dofile("NaowhForever_Professions/CraftQueue.lua")
local queue = assert(ns.Professions.CraftQueue)

queue.Add(C_TradeSkillUI.GetRecipeInfo(100), 2)
local list = queue.List()
assert(list.crafts[100] and list.crafts[100].count == 2, "main craft was not queued")
assert(list.prerequisites[200] and list.prerequisites[200].count == 2, "prerequisite craft was not queued")

local _, missing, missingVendor, vendorCost = queue.Requirements(list.crafts[100])
assert(missing == true, "missing materials were not detected")
assert(missingVendor == true, "missing vendor material was not detected")
assert(vendorCost == 50, "vendor price was not calculated for the missing quantity")
local vendorMaterials = queue.VendorMaterials()
assert(vendorMaterials[1] and vendorMaterials[1].item == 4000 and vendorMaterials[1].qty == 2,
    "vendor-cheaper queue shortage was not listed")
assert(vendorMaterials[1].price == 25, "vendor material price was not included")
inventory[4000] = 1
assert(queue.VendorMaterials()[1].qty == 1, "owned vendor materials were not subtracted")
ahCheaper[4000], inventory[4000] = true, 0
assert(#queue.VendorMaterials() == 0, "AH-cheaper vendor material was still listed for vendor purchase")
ahCheaper[4000] = nil

inventory[5000], inventory[3000], inventory[4000] = 4, 4, 2
queue.Click()
selected = ns.Professions.State.selectedID
assert(selected == 200 and quantity == "2", "prerequisites must be prepared first")
assert(#crafts == 0, "Start Queue must only prepare, not craft")

local event = assert(frames[1].onEvent)
queue.Click()
assert(crafts[1] and crafts[1].id == 200 and crafts[1].count == 2,
    "Craft Next did not request the prepared prerequisite batch")
event(frames[1], "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 200)
inventory[2000] = 2
event(frames[1], "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 200)
assert(ns.Professions.State.selectedID == 100 and quantity == "2", "main craft was not prepared after prerequisites")

queue.Click()
assert(crafts[2] and crafts[2].id == 100 and crafts[2].count == 2,
    "Craft Next did not request the prepared main batch")
event(frames[1], "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 100)
event(frames[1], "UNIT_SPELLCAST_SUCCEEDED", "player", nil, 100)
assert(next(queue.List().prerequisites) == nil and next(queue.List().crafts) == nil,
    "completed crafts remained in the queue")

shoppingList[100] = { name = "Ready", icon = 100, count = 1, need = { [3000] = 2 } }
shoppingList[101] = { name = "Waiting", icon = 101, count = 1, need = { [6000] = 1 } }
shoppingHave[3000] = 2
assert(queue.OnPurchased() == true, "ready shopping craft was not promoted")
assert(shoppingList[100] == nil and shoppingList[101] ~= nil, "promotion did not stay recipe-specific")
assert(queue.List().crafts[100] ~= nil, "promoted craft was not placed in the queue")

shoppingList[102] = { name = "Queued", count = 1, fromQueue = true }
queue.Clear()
assert(next(queue.List().prerequisites) == nil and next(queue.List().crafts) == nil,
    "Clear did not empty the crafting queue")
assert(shoppingList[102] == nil, "Clear did not remove queue-generated shopping entries")
assert(shoppingList[101] ~= nil, "Clear removed an unrelated Shopping List entry")

print("Crafting queue regression test: PASS")
