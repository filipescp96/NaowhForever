-- Regression test for recipe-list cart markers in linked professions.
local function Nothing() end

_G.NaowhForever = {
    THEME = { fg = {}, muted = {}, line = {}, accent = {} },
    L = function(text) return text end,
    Professions = {
        Settings = {},
        State = {},
        Recipes = {},
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

local has = _G.NaowhForever.Professions.List.HasShoppingCraft
assert(has(false) == false, "a linked profession's false sentinel must not be indexed")
assert(has(nil) == false, "a missing shopping entry should not show a cart")
assert(has({ count = 0 }) == false, "an empty shopping entry should not show a cart")
assert(has({ count = "2" }) == true, "a positive shopping count should show a cart")

print("Shopping marker regression test: PASS")
