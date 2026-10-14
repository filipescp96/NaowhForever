-- ForeverAHCount.lua
-- Adds the player's active Auction House quantity to Naowh Forever profession rows.

local ADDON_NAME = ...

local ACTIVE_LEGACY_STATUS = 1 -- Legacy status 1 means the auction has sold.
local FILTER_KEY = "filterProfitableNotSelling"
local FILTER_TEXT = "Profitable & Not Selling"
local FAVORITE_ATLAS = "auctionhouse-icon-favorite"
local FAVORITE_MARKER = " |A:" .. FAVORITE_ATLAS .. ":12:12|a"
local FAVORITE_FALLBACK = " |TInterface\\COMMON\\ReputationStar:12:12:0:0:64:64:0:32:0:32|t"

local addon = {}
_G.ForeverAHCount = addon

local db
local counts = {}
local listHooked = false
local filterHooked = false
local favoriteToggleHooked = false
local merchantUpdateHooked = false
local trainerUpdateHooked = false
local hookedTrainerScrollBox
local requestPending = false
local requestQueued = false
local favoriteRefreshQueued = false
local ItemIDFromLink

local events = CreateFrame("Frame")

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(("|cff0091ed%s:|r %s"):format(ADDON_NAME, message))
end

local function InitializeDatabase()
    if type(_G.ForeverAHCountDB) ~= "table" then
        _G.ForeverAHCountDB = {}
    end

    db = _G.ForeverAHCountDB
    if type(db.counts) ~= "table" then
        db.counts = {}
    end

    counts = db.counts
end

local function RecipeOutputItem(recipeID)
    local ns = _G.NaowhForever
    local recipes = ns and ns.Professions and ns.Professions.Recipes
    if not (recipes and recipes.OutputItem) then return end

    local ok, itemID = pcall(recipes.OutputItem, recipeID)
    if ok then return tonumber(itemID) end
end

local function AuctionCount(itemID)
    if not itemID then return 0 end
    return tonumber(counts[itemID] or counts[tostring(itemID)]) or 0
end

local function ProfitableNotSellingFilterActive()
    local ns = _G.NaowhForever
    local professions = ns and ns.Professions
    return professions
        and professions.Settings.Get(FILTER_KEY) == true
        and professions.Prices.ProfitShown()
end

local function RefreshProfessionDisplay()
    local ns = _G.NaowhForever
    local professions = ns and ns.Professions
    local state = professions and professions.State
    if not (state and state.frame and state.frame.list and professions.List) then return end

    if ProfitableNotSellingFilterActive() and professions.List.RedrawAll then
        professions.List.RedrawAll()
    elseif professions.List.Render then
        professions.List.Render()
    end
end

local function InstallProfessionHook()
    if listHooked then return true end

    local ns = _G.NaowhForever
    local list = ns and ns.Professions and ns.Professions.List
    if not (list and type(list.Render) == "function") then return false end

    list.AuctionCount = function(recipeID)
        return AuctionCount(RecipeOutputItem(recipeID))
    end
    listHooked = true
    return true
end

local function InstallFilter()
    if filterHooked then return true end

    local ns = _G.NaowhForever
    local professions = ns and ns.Professions
    local filters = professions and professions.Filters
    if not (filters and filters.LIST and type(filters.Passes) == "function") then return false end

    local found = false
    for _, filter in ipairs(filters.LIST) do
        if filter.key == FILTER_KEY then
            found = true
            break
        end
    end

    if not found then
        local position = #filters.LIST + 1
        for index, filter in ipairs(filters.LIST) do
            if filter.key == "filterProfit" then
                position = index + 1
                break
            end
        end
        table.insert(filters.LIST, position, {
            key = FILTER_KEY,
            text = FILTER_TEXT,
            profit = true,
        })
    end

    local originalPasses = filters.Passes
    filters.Passes = function(info, unlearned)
        if not originalPasses(info, unlearned) then return false end
        if not ProfitableNotSellingFilterActive() then return true end

        -- The feature is for crafts the player can make, not unlearned recipes.
        if not info then return false end

        local output, made = professions.Recipes.OutputItem(info.recipeID)
        if not output or AuctionCount(output) > 0 then return false end

        local profit = professions.Prices.RecipeProfit(info.recipeID, output, made)
        return profit ~= nil and profit > 0
    end

    filterHooked = true
    return true
end

local function FavoriteMarker()
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(FAVORITE_ATLAS) then
        return FAVORITE_MARKER
    end
    return FAVORITE_FALLBACK
end

local function RemoveFavoriteMarker(value)
    value = value or ""
    for _, marker in ipairs({ FAVORITE_MARKER, FAVORITE_FALLBACK }) do
        local at = value:find(marker, 1, true)
        while at do
            value = value:sub(1, at - 1) .. value:sub(at + #marker)
            at = value:find(marker, 1, true)
        end
    end
    return value
end

local function SetFavoriteMarker(fontString, shown)
    if not (fontString and fontString.GetText and fontString.SetText) then return end
    local name = RemoveFavoriteMarker(fontString:GetText())
    fontString:SetText(shown and (name .. FavoriteMarker()) or name)
end

local function RecipeIsKnown(spellID)
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok, info = pcall(C_TradeSkillUI.GetRecipeInfo, spellID)
        if ok and info and info.learned then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
        if ok and known then return true end
    end
    return false
end

local function FavoriteStore()
    local ns = _G.NaowhForever
    local favorites = ns and ns.ProfFavorites
    if not (favorites and type(favorites.Store) == "function") then return {} end
    local ok, store = pcall(favorites.Store)
    return ok and type(store) == "table" and store or {}
end

local function IsFavoriteSpell(store, spellID)
    return store[spellID] == true or store[tostring(spellID)] == true
end

local function FavoriteVendorItems()
    local ns = _G.NaowhForever
    local store = FavoriteStore()
    local items = {}
    for _, data in pairs((ns and ns.RecipeData) or {}) do
        for _, recipe in ipairs(data.recipes or {}) do
            local spellID, itemID = tonumber(recipe.spell), tonumber(recipe.recipe)
            if spellID and itemID and IsFavoriteSpell(store, spellID) and not RecipeIsKnown(spellID) then
                items[itemID] = true
            end
        end
    end
    return items
end

local function MerchantStock(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and info then return info.numAvailable end
    end
    if type(GetMerchantItemInfo) == "function" then
        local ok, _, _, _, _, available = pcall(GetMerchantItemInfo, index)
        if ok then return available end
    end
end

local function MerchantItemID(index, itemButton)
    if type(GetMerchantItemID) == "function" then
        local ok, itemID = pcall(GetMerchantItemID, index)
        if ok and itemID then return tonumber(itemID) end
    end
    local link = itemButton and itemButton.link
    if not link and type(GetMerchantItemLink) == "function" then
        local ok, result = pcall(GetMerchantItemLink, index)
        if ok then link = result end
    end
    return ItemIDFromLink(link)
end

local function MerchantRowParts(row, fallbackIndex)
    if not row then return end
    local rowName = row.GetName and row:GetName()
    local name = row.Name or (rowName and _G[rowName .. "Name"])
    local itemButton = row.ItemButton or (rowName and _G[rowName .. "ItemButton"])
    local index = itemButton and itemButton.GetID and itemButton:GetID()
    return name, itemButton, tonumber(index) or fallbackIndex
end

local function UpdateMerchantFavoriteMarkers()
    local favoriteItems = FavoriteVendorItems()
    local buyback = _G.MerchantFrame and _G.MerchantFrame.selectedTab == 2
    local seen = {}

    local function Apply(row, fallbackIndex)
        if not row or seen[row] then return end
        seen[row] = true
        local name, itemButton, index = MerchantRowParts(row, fallbackIndex)
        local show = false
        if not buyback and index and (not row.IsShown or row:IsShown()) then
            local itemID = MerchantItemID(index, itemButton)
            local stock = MerchantStock(index)
            show = favoriteItems[itemID] == true and stock ~= 0
        end
        SetFavoriteMarker(name, show)
    end

    local custom = _G.WSkinMerchantScrollFrame
        or (_G.MerchantFrame and _G.MerchantFrame.wSkinScrollFrame)
    for index, row in ipairs((custom and custom.rows) or {}) do Apply(row, index) end

    local perPage = tonumber(_G.MERCHANT_ITEMS_PER_PAGE) or 12
    local page = (_G.MerchantFrame and tonumber(_G.MerchantFrame.page)) or 1
    for slot = 1, perPage do
        Apply(_G["MerchantItem" .. slot], (page - 1) * perPage + slot)
    end
end

local function AvailableFavoriteTrainerNames()
    local ns = _G.NaowhForever
    local patterns = ns and ns.Professions and ns.Professions.Patterns
    if not (patterns and type(patterns.TrainerOffers) == "function") then return {} end
    local ok, offers = pcall(patterns.TrainerOffers)
    local names = {}
    if ok then
        for _, offer in ipairs(offers or {}) do
            if offer.name then names[offer.name] = true end
        end
    end
    return names
end

local function TrainerRowName(row)
    if not row then return end
    local rowName = row.GetName and row:GetName()
    return row.name or row.Name or row.Text or (rowName and (
        _G[rowName .. "Text"] or _G[rowName .. "Name"]))
end

local function UpdateTrainerFavoriteMarkers()
    local names = AvailableFavoriteTrainerNames()
    local seen = {}
    local function Apply(row)
        if not row or seen[row] then return end
        seen[row] = true
        local fontString = TrainerRowName(row)
        local name = fontString and fontString.GetText and RemoveFavoriteMarker(fontString:GetText())
        SetFavoriteMarker(fontString, name and names[name] == true)
    end

    local frame = _G.ClassTrainerFrame
    local scrollBox = frame and (frame.ScrollBox or frame.scrollBox)
    if scrollBox and scrollBox.ForEachFrame then
        pcall(scrollBox.ForEachFrame, scrollBox, Apply)
    end

    local displayed = tonumber(_G.CLASS_TRAINER_SKILLS_DISPLAYED) or 30
    for index = 1, displayed do Apply(_G["ClassTrainerSkill" .. index]) end
end

local function RefreshFavoriteMarkers()
    favoriteRefreshQueued = false
    UpdateMerchantFavoriteMarkers()
    UpdateTrainerFavoriteMarkers()
end

local function QueueFavoriteMarkerRefresh(delay)
    if favoriteRefreshQueued then return end
    favoriteRefreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, RefreshFavoriteMarkers)
    else
        RefreshFavoriteMarkers()
    end
end

local function InstallFavoriteMarkerHooks()
    local ns = _G.NaowhForever
    local favorites = ns and ns.ProfFavorites
    if not favoriteToggleHooked and favorites and type(favorites.Toggle) == "function" then
        hooksecurefunc(favorites, "Toggle", function() QueueFavoriteMarkerRefresh() end)
        favoriteToggleHooked = true
    end

    if not merchantUpdateHooked and type(_G.MerchantFrame_Update) == "function" then
        hooksecurefunc("MerchantFrame_Update", function() QueueFavoriteMarkerRefresh() end)
        merchantUpdateHooked = true
    end

    if not trainerUpdateHooked and type(_G.ClassTrainerFrame_Update) == "function" then
        hooksecurefunc("ClassTrainerFrame_Update", function() QueueFavoriteMarkerRefresh() end)
        trainerUpdateHooked = true
    end

    local trainerFrame = _G.ClassTrainerFrame
    local scrollBox = trainerFrame and (trainerFrame.ScrollBox or trainerFrame.scrollBox)
    if scrollBox and scrollBox ~= hookedTrainerScrollBox and type(scrollBox.Update) == "function" then
        hooksecurefunc(scrollBox, "Update", function() QueueFavoriteMarkerRefresh() end)
        hookedTrainerScrollBox = scrollBox
    end
end

local function InstallIntegrations()
    InstallProfessionHook()
    InstallFilter()
    InstallFavoriteMarkerHooks()
end

local function ReplaceCounts(fresh)
    counts = fresh
    db.counts = fresh
    db.lastScan = time()
    RefreshProfessionDisplay()
end

ItemIDFromLink = function(link)
    return link and tonumber(tostring(link):match("item:(%d+)"))
end

local function ScanLegacyAuctions()
    if type(GetNumAuctionItems) ~= "function" or type(GetAuctionItemInfo) ~= "function" then
        return false
    end

    local fresh = {}
    local total = GetNumAuctionItems("owner")
    total = tonumber(total) or 0

    for index = 1, total do
        local _, _, quantity, _, _, _, _, _, _, _, _, _, _, _, _, saleStatus, itemID =
            GetAuctionItemInfo("owner", index)

        if not itemID and type(GetAuctionItemLink) == "function" then
            itemID = ItemIDFromLink(GetAuctionItemLink("owner", index))
        end

        itemID = tonumber(itemID)
        if itemID and saleStatus ~= ACTIVE_LEGACY_STATUS then
            fresh[itemID] = (fresh[itemID] or 0) + (tonumber(quantity) or 1)
        end
    end

    ReplaceCounts(fresh)
    return true
end

local function ModernAuctionIsActive(info)
    local active = Enum and Enum.AuctionStatus and Enum.AuctionStatus.Active
    if active ~= nil then return info.status == active end
    return info.status ~= ACTIVE_LEGACY_STATUS
end

local function ScanModernAuctions()
    if not (C_AuctionHouse and C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetOwnedAuctionInfo) then
        return false
    end

    local fresh = {}
    local total = C_AuctionHouse.GetNumOwnedAuctions()
    total = tonumber(total) or 0

    for index = 1, total do
        local info = C_AuctionHouse.GetOwnedAuctionInfo(index)
        local itemID = info and info.itemKey and tonumber(info.itemKey.itemID)
        if itemID and ModernAuctionIsActive(info) then
            fresh[itemID] = (fresh[itemID] or 0) + (tonumber(info.quantity) or 1)
        end
    end

    ReplaceCounts(fresh)
    return true
end

local function UsesLegacyAuctionHouse()
    return type(GetNumAuctionItems) == "function"
        and type(GetAuctionItemInfo) == "function"
        and type(GetOwnerAuctionItems) == "function"
end

local function ScanOwnedAuctions()
    if UsesLegacyAuctionHouse() then return ScanLegacyAuctions() end
    return ScanModernAuctions()
end

local function RequestOwnedAuctions()
    requestQueued = false

    if UsesLegacyAuctionHouse() then
        requestPending = false
        pcall(GetOwnerAuctionItems)
        return
    end

    if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then
        local ok = pcall(C_AuctionHouse.QueryOwnedAuctions, {})
        requestPending = not ok
    end
end

local function QueueOwnerRequest(delay)
    requestPending = true
    if requestQueued then return end

    requestQueued = true
    C_Timer.After(delay or 0, RequestOwnedAuctions)
end

local function IsAuctioneerInteraction(interactionType)
    return Enum and Enum.PlayerInteractionType
        and interactionType == Enum.PlayerInteractionType.Auctioneer
end

local function RegisterEvent(name)
    pcall(events.RegisterEvent, events, name)
end

local function OnEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then
        InitializeDatabase()
        InstallIntegrations()
        return
    end

    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded == "NaowhForever_Professions" then
            InstallIntegrations()
        elseif loaded == "Blizzard_MerchantUI" or loaded == "Blizzard_TrainerUI"
            or loaded == "EllesmereUIBlizzardSkin" then
            InstallFavoriteMarkerHooks()
            QueueFavoriteMarkerRefresh()
        end
        return
    end

    if event == "AUCTION_HOUSE_SHOW" then
        QueueOwnerRequest(0.2)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if IsAuctioneerInteraction(...) then QueueOwnerRequest(0.2) end
    elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if requestPending then RequestOwnedAuctions() end
    elseif event == "AUCTION_OWNED_LIST_UPDATE" or event == "OWNED_AUCTIONS_UPDATED" then
        requestPending = false
        ScanOwnedAuctions()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        requestPending = false
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED"
        or event == "AUCTION_CANCELED"
        or event == "AUCTION_HOUSE_AUCTIONS_EXPIRED"
        or event == "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION" then
        QueueOwnerRequest(0.2)
    elseif event == "CHAT_MSG_SYSTEM" then
        local message = ...
        if message == ERR_AUCTION_STARTED or message == ERR_AUCTION_REMOVED then
            QueueOwnerRequest(0.2)
        end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE"
        or event == "TRAINER_SHOW" or event == "TRAINER_UPDATE"
        or event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_SKILL_LINE"
        or event == "TRADE_SKILL_LIST_UPDATE" then
        InstallFavoriteMarkerHooks()
        QueueFavoriteMarkerRefresh()
    end
end

function addon.GetCount(itemID)
    return AuctionCount(tonumber(itemID))
end

function addon.GetLastScanTime()
    return db and db.lastScan
end

function addon.Refresh()
    QueueOwnerRequest(0)
end

SLASH_FOREVERAHCOUNT1 = "/fahc"
SlashCmdList.FOREVERAHCOUNT = function(message)
    message = strtrim(message or ""):lower()
    if message == "refresh" then
        addon.Refresh()
        Print("Auction refresh requested.")
        return
    end

    local lastScan = addon.GetLastScanTime()
    if lastScan then
        Print(("Last Auction House update: %s. Use /fahc refresh while the Auction House is open.")
            :format(date("%Y-%m-%d %H:%M:%S", lastScan)))
    else
        Print("No Auction House data yet. Visit the Auction House once to populate the counts.")
    end
end

events:SetScript("OnEvent", OnEvent)

for _, event in ipairs({
    "PLAYER_LOGIN",
    "ADDON_LOADED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "AUCTION_OWNED_LIST_UPDATE",
    "OWNED_AUCTIONS_UPDATED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "AUCTION_HOUSE_THROTTLED_SYSTEM_READY",
    "AUCTION_HOUSE_AUCTION_CREATED",
    "AUCTION_CANCELED",
    "AUCTION_HOUSE_AUCTIONS_EXPIRED",
    "AUCTION_HOUSE_SHOW_FORMATTED_NOTIFICATION",
    "CHAT_MSG_SYSTEM",
    "MERCHANT_SHOW",
    "MERCHANT_UPDATE",
    "TRAINER_SHOW",
    "TRAINER_UPDATE",
    "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_SKILL_LINE",
    "TRADE_SKILL_LIST_UPDATE",
}) do
    RegisterEvent(event)
end
