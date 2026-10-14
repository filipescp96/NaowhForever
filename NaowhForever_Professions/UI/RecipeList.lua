-- RecipeList.lua: the window's recipe list on the left: headers, your recipes, the unlearned ones, the scrollbar.
local ns = _G.NaowhForever

local T = ns.THEME

local P = ns.Professions
local S = P.Settings
local W = P.State
local R = P.Recipes
local V = P.Vendors
local Prices = P.Prices
local Favorites = P.Favorites
local Entries = P.Entries
local Orders = P.Orders
local Text = P.Text
local Style = P.Style
local Widgets = P.Widgets
local SetColor = Widgets.SetColor
local entries = Entries.list

local ROW_H = Style.ROW_H
local ROUND = P.C.ROUND
local SCROLL_W = 6
local SCROLL_INSET = 2
local SCROLL_STEP = 2
local THUMB_H, THUMB_MIN = 40, 20
local THUMB_ALPHA = 0.8
local ROW_INSET = 2
local ROW_RIGHT_ROOM = SCROLL_W + 6
local ICON_SHRINK = Style.ROW_ICON_SHRINK
local TEXT_GAP = 6
local STAR_GAP = 4
local STAR_SIZE = 12
local AUCTION_GAP, AUCTION_SIZE = 4, 12
local CART_GAP, CART_SIZE = 4, 12
local QUEUE_GAP, QUEUE_SIZE = 4, 12
local BAG_GAP, BAG_SIZE = 4, 12
local QUEUE_ICON = "Interface\\Icons\\Trade_BlackSmithing"
local BAG_ICON = "Interface\\Icons\\INV_Misc_Bag_08"
local AUCTION_ICON = "Interface\\Minimap\\Tracking\\Auctioneer"
local HEAD_X, SUB_HEAD_X = 4, 14
local COUNT_X, COUNT_GAP, ICON_X = 4, 6, 24
local TEXT_HEAD = "%s (%d)"
local TEXT_OPEN, TEXT_CLOSED = "-  ", "+  "
local TEXT_RECIPE = ns.L("Recipe ")
local TEXT_SEPARATOR = " | "
local TEXT_REQUIRED = ns.L("Required skill: %d  (%s)")
local TEXT_BAGS = ns.L("In Bags")
local TEXT_BANK = ns.L("In Bank")
local TEXT_SHOPPING_LIST = ns.L("Shopping List")
local TEXT_CRAFTING_QUEUE = ns.L("Crafting Queue")
local TEXT_AUCTION_HOUSE = AUCTION_HOUSE or ns.L("Auction House")
local TEXT_COUNT = ns.L("%d")

local win
local rows = {}
local ROI_COLORS = {
    negative = Style.RED_RGB,
    muted = T.muted,
    yellow = Style.GOLD_RGB,
    green = Style.PROFIT_RGB,
}

local List = {}
P.List = List

local function VisibleRows()
    return math.max(1, math.floor((win.list:GetHeight()) / ROW_H))
end

local function ListProfit(recipeID, output, made)
    if W.linked or not S.Get("craftProfitList") then return "", T.fg end
    local profit, cost = Prices.RecipeEconomics(recipeID, output, made)
    if profit == nil then return "", T.fg end
    local text = Text.Money(profit, true)
    local roi = Prices.ROI(profit, cost)
    if S.Get("craftROI") and roi and roi >= 0 then
        local color = ROI_COLORS[Prices.ROIBand(roi)] or T.muted
        text = text .. " " .. Text.Hex(color) .. Prices.ROIText(roi) .. "|r"
    end
    return text, profit >= 0 and Style.PROFIT_RGB or Style.RED_RGB
end

local function FormatCraftCount(info)
    local have = R.Craftable(info)
    local plain = have > 0 and tostring(have) or ""
    if not S.Get("vendorMaterials") then return plain end
    local withVendor = V.CraftableWithVendor(info)
    if not withVendor or withVendor <= have then return plain end
    local orange = Text.Hex(Style.VENDOR_RGB) .. withVendor .. "|r"
    if have == 0 then return orange end
    return plain .. TEXT_SEPARATOR .. orange
end

local function ShoppingCount(craft)
    return type(craft) == "table" and math.max(0, tonumber(craft.count) or 0) or 0
end

local function QueuedCount(recipeID)
    local queue = P.CraftQueue
    local list = queue and queue.List and queue.List()
    if type(list) ~= "table" then return 0 end
    local crafts = type(list.crafts) == "table" and list.crafts or {}
    local prerequisites = type(list.prerequisites) == "table" and list.prerequisites or {}
    local craft = crafts[recipeID]
    local prerequisite = prerequisites[recipeID]
    local craftCount = type(craft) == "table" and math.max(0, tonumber(craft.count) or 0) or 0
    local prerequisiteCount = type(prerequisite) == "table" and math.max(0, tonumber(prerequisite.count) or 0) or 0
    return craftCount + prerequisiteCount
end

local function OwnedCounts(recipeID)
    local output = R.OutputItem(recipeID)
    if not output then return 0, 0 end
    return math.max(0, tonumber(R.BagCount(output)) or 0), math.max(0, tonumber(R.BankCount(output)) or 0)
end

local function MarkerCounts(info)
    local shopping = P.Shopping and P.Shopping.List and P.Shopping.List()[info.recipeID]
    local bags, bank = OwnedCounts(info.recipeID)
    local auctions = 0
    if type(List.AuctionCount) == "function" then
        local ok, count = pcall(List.AuctionCount, info.recipeID)
        if ok then auctions = math.max(0, tonumber(count) or 0) end
    end
    return ShoppingCount(shopping), QueuedCount(info.recipeID), bags, bank, auctions
end

local function AlignRows(visible)
    local width = 0
    for i = 1, visible do
        local row, e = rows[i], entries[i + W.offset]
        if row and e and not e.cat then width = math.max(width, row.count:GetStringWidth()) end
    end
    local iconX = math.max(ICON_X, width > 0 and COUNT_X + width + COUNT_GAP or 0)
    for i = 1, visible do
        local row, e = rows[i], entries[i + W.offset]
        if row and e and not e.cat then
            row.count:ClearAllPoints()
            row.count:SetPoint("RIGHT", row, "LEFT", iconX - COUNT_GAP, 0)
            row.icon:SetPoint("LEFT", iconX, 0)
        end
    end
end

local function Scroll(_, delta)
    W.offset = math.min(math.max(0, #entries - VisibleRows()), math.max(0, W.offset - delta * SCROLL_STEP))
    List.Render()
end

local function OnScrollValue(self, value)
    if self.syncing then return end
    W.offset = math.floor(value + ROUND)
    List.Render()
end

local function RedrawAll()
    Entries.Build()
    List.Render()
    P.Detail.Render()
end

local function SelectRecipe(info)
    W.selectedID, W.selectedUnlearned = info.recipeID, nil
    List.Render()
    P.Detail.Render()
end

local function OnRowClick(self, button)
    local e = self.entry
    if button == "RightButton" then
        if (e.recipe or e.unlearned) and not W.linked then
            Favorites.Toggle(e.recipe or e.unlearned)
            RedrawAll()
        end
        return
    end
    if e.cat then
        Entries.Toggle(e.cat)
        Entries.Build()
        List.Render()
    elseif e.unlearned then
        W.selectedUnlearned = e.unlearned
        List.Render()
        P.Detail.Render()
    elseif IsModifiedClick("CHATLINK") then
        local id = e.recipe.recipeID
        P.AH.ShiftClick((R.OutputItem(id)), C_TradeSkillUI.GetRecipeLink(id))
    else
        SelectRecipe(e.recipe)
    end
end

local function OnRowEnter(self)
    local r = self.entry.unlearned
    if r then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetSpellByID(r.spell)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(TEXT_REQUIRED:format(ns.RecipeFinder.Skill(r), ns.RecipeFinder.Tag(r)), 1, 1, 1)
        GameTooltip:Show()
        return
    end
    if not self.entry.recipe then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, self.entry.recipe.recipeID) then
        GameTooltip:SetSpellByID(self.entry.recipe.recipeID)
    end
    GameTooltip:Show()
end

local function MarkerTooltip(self, title, firstLabel, firstCount, secondLabel, secondCount)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title, 1, 1, 1)
    GameTooltip:AddDoubleLine(firstLabel, TEXT_COUNT:format(firstCount),
        T.fg.r, T.fg.g, T.fg.b, T.accent.r, T.accent.g, T.accent.b)
    if secondLabel then
        GameTooltip:AddDoubleLine(secondLabel, TEXT_COUNT:format(secondCount),
            T.fg.r, T.fg.g, T.fg.b, T.accent.r, T.accent.g, T.accent.b)
    end
    GameTooltip:Show()
end

local function Marker(row, size)
    local marker = CreateFrame("Button", nil, row)
    marker:SetSize(size, size)
    marker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    marker:SetScript("OnClick", function(_, button) OnRowClick(row, button) end)
    marker:SetScript("OnLeave", GameTooltip_Hide)
    return marker
end

local function NewRow(i)
    local row = CreateFrame("Button", nil, win.list)
    row:SetSize(Style.LEFT_W - ROW_RIGHT_ROOM, ROW_H)
    row:SetPoint("TOPLEFT", ROW_INSET, -ROW_INSET - (i - 1) * ROW_H)
    row.head = ns.Solid(row, "BACKGROUND", T.line, Style.PANEL_ALPHA)
    row.head:SetAllPoints()
    row.sel = ns.Solid(row, "BACKGROUND", T.accent, Style.SELECTED_ALPHA)
    row.sel:SetAllPoints()
    row.hl = ns.Solid(row, "HIGHLIGHT", T.fg, Style.HIGHLIGHT_ALPHA)
    row.hl:SetAllPoints()
    row.icon = Widgets.Crop(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetSize(ROW_H - ICON_SHRINK, ROW_H - ICON_SHRINK)
    row.profit = ns.Font(row, Style.FONT, nil)
    row.profit:SetPoint("RIGHT", -TEXT_GAP, 0)
    row.profit:SetJustifyH("RIGHT")
    row.count = ns.Font(row, Style.FONT, nil)
    row.count:SetJustifyH("RIGHT")
    row.text = ns.Font(row, Style.FONT, nil)
    row.text:SetPoint("RIGHT", row.profit, "LEFT", -TEXT_GAP, 0)
    row.fav = row:CreateTexture(nil, "OVERLAY")
    row.fav:SetSize(STAR_SIZE, STAR_SIZE)
    row.fav:SetPoint("RIGHT", row.profit, "LEFT", -STAR_GAP, 0)
    Widgets.Star(row.fav, true)
    row.fav:Hide()
    row.auction = Marker(row, AUCTION_SIZE)
    row.auction.icon = Widgets.Crop(row.auction:CreateTexture(nil, "OVERLAY"))
    row.auction.icon:SetAllPoints()
    row.auction.icon:SetTexture(AUCTION_ICON)
    row.auction:Hide()
    row.auction:SetScript("OnEnter", function(self)
        MarkerTooltip(self, self.itemName or TEXT_AUCTION_HOUSE, TEXT_AUCTION_HOUSE, self.count or 0)
    end)
    row.cart = Marker(row, CART_SIZE)
    local function CartPart(width, height, x, y)
        local part = row.cart:CreateTexture(nil, "OVERLAY")
        part:SetSize(width, height)
        part:SetPoint("TOPLEFT", x, y)
        part:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, 1)
    end
    CartPart(4, 2, 0, -1)  -- handle
    CartPart(2, 6, 3, -2)  -- handle stem
    CartPart(8, 5, 4, -3)  -- basket
    CartPart(8, 1, 4, -8)  -- axle
    CartPart(2, 2, 5, -10) -- wheels
    CartPart(2, 2, 10, -10)
    row.cart:Hide()
    row.cart:SetScript("OnEnter", function(self)
        MarkerTooltip(self, TEXT_SHOPPING_LIST, TEXT_SHOPPING_LIST, self.count or 0)
    end)
    row.craftQueue = Marker(row, QUEUE_SIZE)
    row.craftQueue.icon = Widgets.Crop(row.craftQueue:CreateTexture(nil, "OVERLAY"))
    row.craftQueue.icon:SetAllPoints()
    row.craftQueue.icon:SetTexture(QUEUE_ICON)
    row.craftQueue:Hide()
    row.craftQueue:SetScript("OnEnter", function(self)
        MarkerTooltip(self, TEXT_CRAFTING_QUEUE, TEXT_CRAFTING_QUEUE, self.count or 0)
    end)
    row.bag = Marker(row, BAG_SIZE)
    row.bag.icon = Widgets.Crop(row.bag:CreateTexture(nil, "OVERLAY"))
    row.bag.icon:SetAllPoints()
    row.bag.icon:SetTexture(BAG_ICON)
    row.bag:Hide()
    row.bag:SetScript("OnEnter", function(self)
        MarkerTooltip(self, self.itemName or TEXT_BAGS, TEXT_BAGS, self.bags or 0, TEXT_BANK, self.bank or 0)
    end)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row:SetScript("OnClick", OnRowClick)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    row:SetScript("OnMouseWheel", Scroll)
    return row
end

local function TextBeforeMarkers(row, fav, auctions, cart, queued, owned)
    row.fav:SetShown(fav)
    row.auction:SetShown(auctions > 0)
    row.cart:SetShown(cart > 0)
    row.craftQueue:SetShown(queued > 0)
    row.bag:SetShown(owned)
    row.cart.count = cart
    row.auction.count = auctions
    row.craftQueue.count = queued
    row.fav:ClearAllPoints()
    row.auction:ClearAllPoints()
    row.cart:ClearAllPoints()
    row.craftQueue:ClearAllPoints()
    row.bag:ClearAllPoints()
    local anchor = row.profit
    if fav then
        row.fav:SetPoint("RIGHT", anchor, "LEFT", -STAR_GAP, 0)
        anchor = row.fav
    end
    if auctions > 0 then
        row.auction:SetPoint("RIGHT", anchor, "LEFT", -AUCTION_GAP, 0)
        anchor = row.auction
    end
    if cart > 0 then
        row.cart:SetPoint("RIGHT", anchor, "LEFT", -CART_GAP, 0)
        anchor = row.cart
    end
    if queued > 0 then
        row.craftQueue:SetPoint("RIGHT", anchor, "LEFT", -QUEUE_GAP, 0)
        anchor = row.craftQueue
    end
    if owned then
        row.bag:SetPoint("RIGHT", anchor, "LEFT", -BAG_GAP, 0)
        anchor = row.bag
    end
    local gap = (fav or auctions > 0 or cart > 0 or queued > 0 or owned) and QUEUE_GAP or TEXT_GAP
    row.text:SetPoint("RIGHT", anchor, "LEFT", -gap, 0)
end

local function FillHeader(row, cat)
    local label = cat.count and TEXT_HEAD:format(cat.name, cat.count) or cat.name
    row.text:SetText((Entries.IsCollapsed(cat) and TEXT_CLOSED or TEXT_OPEN) .. label)
    SetColor(row.text, Style.GOLD_RGB)
    row.text:SetPoint("LEFT", cat.sub and SUB_HEAD_X or HEAD_X, 0)
    row.count:SetText("")
    row.profit:SetText("")
    row.icon:Hide()
    row.fav:Hide()
    row.auction:Hide()
    row.cart:Hide()
    row.craftQueue:Hide()
    row.bag:Hide()
    row.text:SetPoint("RIGHT", row.profit, "LEFT", -TEXT_GAP, 0)
    row.head:Show()
    row.sel:Hide()
end

local function FillUnlearned(row, r)
    local c = ns.RecipeFinder.Color(r)
    row.icon:SetTexture((r.item and C_Item.GetItemIconByID(r.item)) or C_Spell.GetSpellTexture(r.spell))
    row.icon:Show()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", TEXT_GAP, 0)
    row.text:SetText(C_Spell.GetSpellName(r.spell) or (TEXT_RECIPE .. r.spell))
    SetColor(row.text, c)
    row.count:SetText(ns.RecipeFinder.Skill(r))
    SetColor(row.count, c)
    local read, made = R.OutputItem(r.spell)
    local profit, color = ListProfit(r.spell, r.item or read, made)
    row.profit:SetText(profit)
    SetColor(row.profit, color)
    TextBeforeMarkers(row, Favorites.Is(r), 0, 0, 0, false)
    row.head:Hide()
    row.sel:SetShown(r == W.selectedUnlearned)
end

local function FillRecipe(row, info)
    SetColor(row.count, T.fg)
    row.icon:SetTexture(info.icon)
    row.icon:Show()
    row.text:SetPoint("LEFT", row.icon, "RIGHT", TEXT_GAP, 0)
    row.text:SetText(info.name)
    SetColor(row.text, Style.DIFFICULTY_RGB[info.relativeDifficulty] or T.fg)
    row.count:SetText(W.linked and Orders.Count(info.recipeID) or FormatCraftCount(info))
    local shopping, queued, bags, bank, auctions = List.MarkerCounts(info)
    row.bag.bags, row.bag.bank, row.bag.itemName = bags, bank, info.name
    row.auction.itemName = info.name
    TextBeforeMarkers(row, not W.linked and Favorites.Is(info), not W.linked and auctions or 0,
        not W.linked and shopping or 0,
        not W.linked and queued or 0, not W.linked and (bags > 0 or bank > 0))
    local profit, color = ListProfit(info.recipeID, R.OutputItem(info.recipeID))
    row.profit:SetText(profit)
    SetColor(row.profit, color)
    row.head:Hide()
    row.sel:SetShown(not W.selectedUnlearned and info.recipeID == W.selectedID)
end

local function FillRow(i, e)
    local row = rows[i]
    if not row then
        row = NewRow(i)
        rows[i] = row
    end
    row.entry = e
    row.icon:ClearAllPoints()
    if e.cat then
        FillHeader(row, e.cat)
    elseif e.unlearned then
        FillUnlearned(row, e.unlearned)
    else
        FillRecipe(row, e.recipe)
    end
    row:Show()
end

local function SyncScrollbar(visible)
    local bar, maxOffset = win.scroll, math.max(0, #entries - visible)
    if not bar then return end
    bar:SetShown(maxOffset > 0)
    if maxOffset <= 0 then return end
    bar.thumb:SetHeight(math.max(THUMB_MIN, bar:GetHeight() * visible / #entries))
    bar.syncing = true
    bar:SetMinMaxValues(0, maxOffset)
    bar:SetValue(W.offset)
    bar.syncing = nil
end

function List.Render()
    local visible = VisibleRows()
    W.offset = math.min(W.offset, math.max(0, #entries - visible))
    for i = 1, visible do
        local e = entries[i + W.offset]
        if e then
            FillRow(i, e)
        elseif rows[i] then
            rows[i]:Hide()
        end
    end
    for i = visible + 1, #rows do rows[i]:Hide() end
    AlignRows(visible)
    SyncScrollbar(visible)
end

function List.UpdateShoppingMarkers()
    if win and win.list then List.Render() end
end

function List.Build(frame, below)
    win = frame
    local list = CreateFrame("Frame", nil, win)
    list:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -TEXT_GAP)
    list:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", Style.PAD, Style.PAD)
    list:SetWidth(Style.LEFT_W)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", Scroll)
    ns.Solid(list, "BACKGROUND", T.panel, Style.PANEL_ALPHA):SetAllPoints()
    win.list = list

    local bar = CreateFrame("Slider", nil, list)
    bar:SetPoint("TOPRIGHT", -SCROLL_INSET, -SCROLL_INSET)
    bar:SetPoint("BOTTOMRIGHT", -SCROLL_INSET, SCROLL_INSET)
    bar:SetWidth(SCROLL_W)
    bar:SetOrientation("VERTICAL")
    bar:SetValueStep(1)
    ns.Solid(bar, "BACKGROUND", T.line, Style.PANEL_ALPHA):SetAllPoints()
    bar.thumb = bar:CreateTexture(nil, "ARTWORK")
    bar.thumb:SetColorTexture(T.accent.r, T.accent.g, T.accent.b, THUMB_ALPHA)
    bar.thumb:SetSize(SCROLL_W, THUMB_H)
    bar:SetThumbTexture(bar.thumb)
    bar:SetScript("OnValueChanged", OnScrollValue)
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", Scroll)
    win.scroll = bar
end

List.RedrawAll = RedrawAll
List.MarkerCounts = MarkerCounts
