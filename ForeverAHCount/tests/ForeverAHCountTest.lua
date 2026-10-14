-- Minimal WoW API harness for ForeverAHCount.lua.

local eventFrame
local requests = 0
local auctions = {
    { quantity = 5, status = 0, itemID = 501 },
    { quantity = 3, status = 1, itemID = 501 },
}
local settings = {}
local redraws = 0
local favoriteStore = { [201] = true }
local knownRecipes = {}
local merchantAvailable = -1

local text = { value = "" }
function text:SetText(value) self.value = value end
function text:GetText() return self.value end

local row = {
    entry = { recipe = { recipeID = 101, name = "Test Item" } },
    text = text,
}

local listFrame = {}
function listFrame:GetChildren() return row end

local merchantText = { value = "Pattern: Test Favorite" }
function merchantText:SetText(value) self.value = value end
function merchantText:GetText() return self.value end
local merchantButton = { link = "|Hitem:701|h[Pattern: Test Favorite]|h" }
function merchantButton:GetID() return 1 end
MerchantItem1 = { Name = merchantText, ItemButton = merchantButton }
function MerchantItem1:IsShown() return true end

local trainerText = { value = "Test Favorite" }
function trainerText:SetText(value) self.value = value end
function trainerText:GetText() return self.value end
ClassTrainerSkill1 = { Text = trainerText }
CLASS_TRAINER_SKILLS_DISPLAYED = 1
MERCHANT_ITEMS_PER_PAGE = 1
MerchantFrame = { selectedTab = 1, page = 1 }

NaowhForever = {
    RecipeData = {
        [165] = { recipes = { { spell = 201, recipe = 701 } } },
    },
    ProfFavorites = {
        Store = function() return favoriteStore end,
        Toggle = function(info)
            favoriteStore[info.spell] = not favoriteStore[info.spell]
        end,
    },
    Professions = {
        State = { linked = false, frame = { list = listFrame } },
        Settings = {
            Get = function(key) return settings[key] end,
            Set = function(key, value) settings[key] = value end,
        },
        Recipes = {
            OutputItem = function(recipeID)
                if recipeID == 101 then return 501, 1 end
                if recipeID == 102 then return 502, 1 end
            end,
        },
        Prices = {
            ProfitShown = function() return true end,
            RecipeProfit = function(recipeID)
                return recipeID == 101 and 100 or -100
            end,
        },
        Filters = {
            LIST = {
                { key = "filterFavorite", text = "Favorites" },
                { key = "filterMaterials", text = "Have Materials" },
                { key = "filterSkillUp", text = "Has Skill-Up" },
                { key = "filterProfit", text = "Profitable", profit = true },
                { key = "filterBoE", text = "Bind on Equip", divider = true },
            },
            Passes = function() return true end,
        },
        List = {},
        Patterns = {
            TrainerOffers = function()
                if favoriteStore[201] and not knownRecipes[201] then
                    return { { name = "Test Favorite", spell = 201 } }
                end
                return {}
            end,
        },
    },
}

function NaowhForever.Professions.List.Render()
    row.text:SetText(row.entry.recipe.name)
end

function NaowhForever.Professions.List.RedrawAll()
    redraws = redraws + 1
    NaowhForever.Professions.List.Render()
end

function CreateFrame()
    eventFrame = {}
    function eventFrame:RegisterEvent() end
    function eventFrame:SetScript(kind, callback) self[kind] = callback end
    return eventFrame
end

function hooksecurefunc(target, key, callback)
    local original = target[key]
    target[key] = function(...)
        local results = { original(...) }
        callback(...)
        return table.unpack(results)
    end
end

function GetNumAuctionItems(view)
    assert(view == "owner")
    return #auctions, #auctions
end

function GetAuctionItemInfo(view, index)
    assert(view == "owner")
    local auction = auctions[index]
    return "Test Item", nil, auction.quantity, nil, nil, nil, nil, nil, nil,
        nil, nil, nil, nil, nil, nil, auction.status, auction.itemID, true
end

function GetAuctionItemLink(view, index)
    assert(view == "owner")
    return "|Hitem:" .. auctions[index].itemID .. "|h[Test Item]|h"
end

function GetOwnerAuctionItems()
    requests = requests + 1
end

C_AuctionHouse = {}
C_MerchantFrame = {
    GetItemInfo = function()
        return { numAvailable = merchantAvailable }
    end,
}
C_TradeSkillUI = {
    GetRecipeInfo = function(spellID)
        return { learned = knownRecipes[spellID] == true }
    end,
}
C_SpellBook = { IsSpellKnown = function() return false end }
C_Timer = { After = function(_, callback) callback() end }
Enum = { PlayerInteractionType = { Auctioneer = 1 } }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
ERR_AUCTION_STARTED = "started"
ERR_AUCTION_REMOVED = "removed"

function strtrim(value) return value:match("^%s*(.-)%s*$") end
function time() return 12345 end
function date() return "date" end
function GetMerchantItemID(index) return index == 1 and 701 end
function GetMerchantItemLink(index) return index == 1 and merchantButton.link end

local chunk = assert(loadfile("../ForeverAHCount.lua"))
chunk("ForeverAHCount")

assert(eventFrame.OnEvent, "event handler was not installed")
eventFrame:OnEvent("PLAYER_LOGIN")

local filters = NaowhForever.Professions.Filters
assert(filters.LIST[5].key == "filterProfitableNotSelling",
    "the new filter should be directly below Profitable")

NaowhForever.Professions.Settings.Set("filterProfitableNotSelling", true)
assert(filters.Passes({ recipeID = 101 }), "a profitable recipe with no auctions should pass")
assert(not filters.Passes({ recipeID = 102 }), "an unprofitable recipe should not pass")
assert(not filters.Passes(nil, { spell = 101 }), "unlearned recipes should not pass")

eventFrame:OnEvent("AUCTION_OWNED_LIST_UPDATE")

assert(ForeverAHCount.GetCount(501) == 5, "only active item quantities should be counted")
assert(NaowhForever.Professions.List.AuctionCount(101) == 5,
    "the recipe-list auction marker provider should return the active quantity")
assert(row.text.value == "Test Item", "the auction marker should not modify the recipe name")
assert(ForeverAHCountDB.lastScan == 12345, "the scan time should be persisted")
assert(not filters.Passes({ recipeID = 101 }), "a currently listed recipe should not pass the new filter")
assert(redraws == 1, "an auction update should rebuild the list while the filter is active")

auctions = {}
eventFrame:OnEvent("AUCTION_OWNED_LIST_UPDATE")

assert(ForeverAHCount.GetCount(501) == 0, "a sold or removed item should disappear after an owner update")
assert(NaowhForever.Professions.List.AuctionCount(101) == 0,
    "the auction marker provider should clear recipes with no active auction")
assert(filters.Passes({ recipeID = 101 }), "a profitable recipe should return when its auction is gone")
assert(redraws == 2, "removing an auction should rebuild the filtered list")

eventFrame:OnEvent("AUCTION_HOUSE_SHOW")
assert(requests == 1, "opening the Auction House should request the owner list")

eventFrame:OnEvent("MERCHANT_SHOW")
assert(merchantText.value:find("ReputationStar", 1, true),
    "an in-stock vendor pattern for an unlearned favorite should be starred")

eventFrame:OnEvent("TRAINER_SHOW")
assert(trainerText.value:find("ReputationStar", 1, true),
    "an available favorite trainer recipe should be starred")

merchantAvailable = 0
eventFrame:OnEvent("MERCHANT_UPDATE")
assert(not merchantText.value:find("ReputationStar", 1, true),
    "a sold-out vendor pattern should not stay starred")

merchantAvailable = -1
knownRecipes[201] = true
eventFrame:OnEvent("SPELLS_CHANGED")
assert(not merchantText.value:find("ReputationStar", 1, true),
    "a learned vendor recipe should not stay starred")
assert(not trainerText.value:find("ReputationStar", 1, true),
    "a learned trainer recipe should not stay starred")

knownRecipes[201] = false
NaowhForever.ProfFavorites.Toggle({ spell = 201 })
assert(not merchantText.value:find("ReputationStar", 1, true),
    "removing the favorite should clear the vendor marker")
assert(not trainerText.value:find("ReputationStar", 1, true),
    "removing the favorite should clear the trainer marker")

print("ForeverAHCount tests: PASS")
