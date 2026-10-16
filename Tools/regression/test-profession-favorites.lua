-- Recipe favorites are independent per character and migrate once from their former profile store.
local account = {}
local profile = { craftFavorites = { [100] = true } }
local playerName = "Tester"

local ns = {
    AccountSettings = function() return account end,
    Professions = {
        Settings = { DB = function() return profile end },
    },
}
local env = setmetatable({
    NaowhForever = ns,
    UNKNOWNOBJECT = "Unknown",
    UnitName = function() return playerName end,
    GetRealmName = function() return "Realm" end,
    C_TradeSkillUI = { SetRecipeFavorite = function() end },
}, { __index = _G })
env._G = env

local Load = dofile("Tools/regression/load_files.lua")
Load({ "NaowhForever_Professions/Favorites.lua" }, env)
local favorites = assert(ns.Professions.Favorites)

assert(favorites.Store()[100] == true, "profile favorites were not migrated to the current character")
assert(profile.craftFavorites == nil, "the shared legacy favorite store remained active after migration")
favorites.Toggle({ spell = 101 })
assert(favorites.Store()[101] == true, "the current character's favorite was not saved")

playerName = "Alt"
assert(next(favorites.Store()) == nil, "another character inherited recipe favorites")
favorites.Toggle({ spell = 102 })
assert(favorites.Store()[102] == true and favorites.Store()[101] == nil,
    "the second character did not get independent recipe favorites")

playerName = "Tester"
assert(favorites.Store()[100] and favorites.Store()[101] and not favorites.Store()[102],
    "switching back did not restore the first character's favorites")

playerName = "Unknown"
assert(next(favorites.Store()) == nil, "an unknown character identity exposed another character's favorites")

print("Profession favorites character-state regression test: PASS")
