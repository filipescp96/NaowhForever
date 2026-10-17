-- Loads Disenchant.lua against two copies of one item and checks failures and locks stay per copy.
local saved = {}

_G.NaowhForever = {
    AccountSettings = function() return saved end,
    Professions = {},
}

_G.C_Container = {
    GetContainerNumSlots = function() return 0 end,
    GetContainerItemInfo = function() end,
}
_G.C_Item = {
    GetItemInfoInstant = function() end,
    GetItemQualityByID = function() end,
}
_G.C_SpellBook = { IsSpellKnown = function() return true end }
_G.NUM_BAG_SLOTS = 4
_G.BACKPACK_CONTAINER = 0

dofile("NaowhForever_Professions/Disenchant.lua")

local disenchant = _G.NaowhForever.Professions.Disenchant
local first = { bag = 0, slot = 1, itemID = 100, guid = "first", failureKey = "first", locked = false }
local second = { bag = 0, slot = 2, itemID = 100, guid = "second", failureKey = "second", locked = false }

disenchant.MarkFailed(first)
assert(disenchant.Failed(first), "the refused copy was not remembered")
assert(not disenchant.Failed(second), "another copy of the same item was refused")
assert(disenchant.Ready(second), "the unaffected copy was not ready")

second.locked = true
assert(not disenchant.Ready(second), "a locked item was ready")

local source = assert(io.open("NaowhForever_Professions/UI/Disenchant.lua", "rb")):read("*a")
assert(not source:find("SpellStopTargeting%s*%(") , "the UI calls the protected stop function")
assert(source:find("/stopspelltarget", 1, true), "the secure click does not clear a refused target")
assert(source:find("/use %d %d", 1, true), "the secure macro does not target its bag slot")

print("Profession disenchant regression test: PASS")
