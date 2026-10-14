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
            ItemCount = function(id) return id == 100 and 99 or 0 end,
            BagCount = function(id) return id == 100 and 3 or 0 end,
            BankCount = function(id) return id == 100 and 7 or 0 end,
        },
        Shopping = { List = function() return { [10] = { count = "2" } } end },
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

dofile("../../NaowhForever_Professions/UI/RecipeList.lua")

_G.NaowhForever.Professions.CraftQueue = { List = function()
    return { crafts = { [10] = { count = 2 } }, prerequisites = { [10] = { count = 1 }, [20] = { count = 1 } } }
end }
local counts = _G.NaowhForever.Professions.List.MarkerCounts
_G.NaowhForever.Professions.List.AuctionCount = function(id) return id == 10 and 4 or 0 end
local shopping, queued, bags, bank, auctions = counts({ recipeID = 10 })
assert(shopping == 2, "shopping marker count was not normalized")
assert(queued == 3, "queue marker did not total regular and prerequisite crafts")
assert(bags == 3 and bank == 7, "bag and bank marker counts were not returned")
assert(auctions == 4, "auction marker count was not returned")
local noShopping, noQueue, emptyBags, emptyBank, noAuctions = counts({ recipeID = 30 })
assert(noShopping == 0 and noQueue == 0, "empty shopping and queue markers must remain hidden")
assert(emptyBags == 0 and emptyBank == 0, "recipes without an output item must not show an ownership marker")
assert(noAuctions == 0, "recipes without active auctions must not show an auction marker")

print("Shopping marker regression test: PASS")
