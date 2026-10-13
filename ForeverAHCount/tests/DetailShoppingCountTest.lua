-- Regression test for selecting an unlearned recipe while the Shopping List is visible.
local selected = false
local shown

local function Frame()
    return { SetScript = function() end }
end

CreateFrame = Frame
PROFESSIONS_TRACK_RECIPE = nil

local ns = {
    THEME = { fg = {}, muted = {} },
    L = function(text) return text end,
    Professions = {
        Settings = {},
        C = {},
        State = { linked = false },
        Recipes = { SelectedInfo = function() return selected end },
        Vendors = {},
        Favorites = {},
        Text = {},
        Style = {},
        Widgets = {},
        Shopping = { List = function() return {} end },
    },
}
_G.NaowhForever = ns

dofile("../../NaowhForever_Professions/UI/Detail.lua")

local count = {
    SetShown = function(_, value) shown = value end,
}
local fakeWindow = { detail = { shoppingCount = count } }
local update = assert(ns.Professions.Detail.UpdateShoppingCount)
for i = 1, 20 do
    local name = debug.getupvalue(update, i)
    if name == "win" then
        debug.setupvalue(update, i, fakeWindow)
        break
    end
end

local ok, err = pcall(update)
assert(ok, err)
assert(shown == false, "shopping count should be hidden for an unlearned recipe")

print("Detail shopping-count regression test: PASS")
