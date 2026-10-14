-- Vendor materials belong on the AH shopping list only when the scanned AH unit price is cheaper.
local account = { profVendorPrices = { [10] = 100 } }
local auction = { [10] = 50, [11] = 75 }

function wipe(t) for key in pairs(t) do t[key] = nil end return t end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function GetProfessions() return nil end
function GetSpellBaseCooldown() return 0 end
C_Item = {
    GetItemNameByID = function(id) return "Item " .. id end,
    RequestLoadItemDataByID = function() end,
}
C_TradeSkillUI = {
    GetRecipeCooldown = function() return nil end,
}

local ns = {
    L = function(text) return text end,
    Print = function() end,
    AuctionPrice = function(id) return auction[id] end,
    AccountSettings = function() return account end,
    ProfWindowAPI = {
        IsVendorItem = function(id) return id == 10 end,
        Owned = function() return {} end,
        Reagents = function() return { { itemID = 10, need = 1 }, { itemID = 11, need = 1 } } end,
    },
    Professions = {
        C = { MAX_CRAFTS = 999, MAX_ITEMS = 9999, SKILL_LINE_INDEX = 7 },
        Text = { Short = tostring },
        CooldownRecipes = {},
    },
}
_G.NaowhForever = ns

dofile("NaowhForever_Professions/ShoppingPlan.lua")
local shopping = assert(ns.Professions.Shopping)

assert(shopping.ShouldBuyAH(10) == true, "AH-cheaper vendor material should be bought on the AH")
auction[10] = 150
assert(shopping.ShouldBuyAH(10) == false, "vendor-cheaper material should stay off the AH list")
assert(shopping.ShouldBuyAH(11) == true, "ordinary materials should stay eligible for the AH list")

auction[10] = 50
shopping.Add({ recipeID = 1, name = "Test", icon = 1 }, 1, nil, true)
local craft = shopping.List()[1]
assert(craft.need[10] == 1 and craft.need[11] == 1, "AH-cheaper vendor material was omitted from recipe needs")

local stepped, removed, cleared
ns.Professions.CraftQueue = {
    Step = function(recipeID, prerequisite, by)
        stepped = { recipeID, prerequisite, by }
    end,
    Remove = function(recipeID, prerequisite)
        removed = { recipeID, prerequisite }
    end,
    Clear = function() cleared = true end,
}
craft.fromQueue = true
shopping.Step(1, 1)
assert(stepped and stepped[1] == 1 and stepped[2] == false and stepped[3] == 1,
    "editing a queue-backed shopping craft did not update the crafting queue")
shopping.Remove(1)
assert(removed and removed[1] == 1 and removed[2] == false,
    "removing a queue-backed shopping craft did not update the crafting queue")

shopping.Add({ recipeID = 2, name = "Clear Test", icon = 2 }, 1, nil, true)
shopping.AddItem(11, 2)
shopping.Clear()
assert(cleared, "clearing the Shopping List did not clear its queue-backed demand")
assert(next(shopping.List()) == nil and next(shopping.Manual()) == nil,
    "clearing the Shopping List left crafts or manually added items behind")

print("Shopping plan vendor-price regression test: PASS")
