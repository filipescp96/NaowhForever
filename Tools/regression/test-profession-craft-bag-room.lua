-- Craft requests stop or shrink before Blizzard's protected call when the output will not fit.
local crafted, messages, room = {}, {}, 2
local selected = 77

local ns = {
    L = function(text) return text end,
    Print = function(text) messages[#messages + 1] = text end,
    CraftBagRoom = function(output, made, reagents, limit)
        assert(output == 700 and made == 1 and reagents[1].itemID == 701 and limit > 0,
            "the bag-room check did not receive the selected recipe")
        return room
    end,
    Professions = {
        Settings = { DB = function() return {} end },
        State = { selectedID = selected },
        Links = { Viewing = function() return false end },
    },
}

local tradeSkill = {
    GetRecipeInfo = function(id) return id == selected and { recipeID = id } or nil end,
    GetRecipeSchematic = function(id)
        if id ~= selected then return end
        return { outputItemID = 700, quantityMin = 1, reagentSlotSchematics = {
            { required = true, quantityRequired = 1, reagents = { { itemID = 701 } } },
        } }
    end,
    CraftRecipe = function(id, count) crafted[#crafted + 1] = { id = id, count = count } end,
}

local env = setmetatable({
    NaowhForever = ns,
    C_Item = {},
    C_TradeSkillUI = tradeSkill,
    ERR_INV_FULL = "Inventory is full.",
    wipe = function(t) for key in pairs(t) do t[key] = nil end return t end,
}, { __index = _G })
env._G = env

local Load = dofile("Tools/regression/load_files.lua")
Load({ "NaowhForever_Professions/Recipes.lua" }, env)
local recipes = assert(ns.Professions.Recipes)

assert(recipes.Craft(5) and crafted[1].count == 2,
    "a safe partial batch was not capped to the available bag room")
room = 0
assert(not recipes.Craft(1) and #crafted == 1,
    "a full bag still reached Blizzard's protected craft call")
assert(messages[#messages] == env.ERR_INV_FULL, "the full-bag craft did not explain why it was blocked")
room = nil
assert(recipes.Craft(5) and crafted[2].count == 5,
    "a recipe whose output room cannot be determined was incorrectly blocked")

print("Craft bag-room regression test: PASS")
