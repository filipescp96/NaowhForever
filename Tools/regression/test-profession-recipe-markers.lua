-- Regression test for recipe-list cart markers in linked professions.
local function Nothing() end

_G.NaowhForever = {
    THEME = { fg = {}, muted = {}, line = {}, accent = {} },
    L = function(text) return text end,
    Professions = {
        Settings = {},
        State = {},
        Recipes = {
            OutputItem = function(id) return id == 10 and 100 end,
            ItemCount = function(id) return id == 100 and 3 or 0 end,
            BankCount = function(id) return id == 100 and 7 or 0 end,
        },
        Vendors = {},
        Prices = {},
        Favorites = {},
        Entries = { list = {} },
        Orders = {},
        Text = {},
        Style = {
            ROW_H = 20,
            ROW_ICON_SHRINK = 4,
            RED_RGB = {},
            GOLD_RGB = {},
            PROFIT_RGB = {},
        },
        Widgets = { SetColor = Nothing },
        C = { ROUND = 0.5 },
    },
}

dofile("NaowhForever_Professions/UI/RecipeList.lua")

local has = _G.NaowhForever.Professions.List.HasShoppingCraft
assert(has(false) == false, "a linked profession's false sentinel must not be indexed")
assert(has(nil) == false, "a missing shopping entry should not show a cart")
assert(has({ count = 0 }) == false, "an empty shopping entry should not show a cart")
assert(has({ count = "2" }) == true, "a positive shopping count should show a cart")
assert(_G.NaowhForever.Professions.List.ShoppingCount({ count = "2" }) == 2,
    "shopping tooltip count was not normalized")

local queued = _G.NaowhForever.Professions.List.HasQueuedCraft
_G.NaowhForever.Professions.CraftQueue = { List = function()
    return { crafts = { [10] = { count = 2 } }, prerequisites = { [10] = { count = 1 }, [20] = { count = 1 } } }
end }
assert(queued(10) == true, "a regular queued craft should show the crafting icon")
assert(queued(20) == true, "a prerequisite craft should show the crafting icon")
assert(queued(30) == false, "an unqueued recipe should not show the crafting icon")
assert(_G.NaowhForever.Professions.List.QueuedCount(10) == 3,
    "crafting queue tooltip did not total regular and prerequisite crafts")

local bags, bank = _G.NaowhForever.Professions.List.OwnedCounts(10)
assert(bags == 3 and bank == 7, "bag and bank tooltip counts were not returned")
local emptyBags, emptyBank = _G.NaowhForever.Professions.List.OwnedCounts(30)
assert(emptyBags == 0 and emptyBank == 0, "recipes without an output item must not show an ownership marker")

print("Shopping marker regression test: PASS")
