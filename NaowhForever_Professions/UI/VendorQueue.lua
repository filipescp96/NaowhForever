-- VendorQueue.lua: queue-required merchant reagents beside an open vendor, with click-to-buy controls.
local ns = _G.NaowhForever

local T = ns.THEME

local P = ns.Professions
local S = P.Settings
local V = P.Vendors
local Shopping = P.Shopping
local Text = P.Text
local Style = P.Style
local Widgets = P.Widgets

local WIDTH = Style.POPUP_W
local ROW_H, MAX_VISIBLE = 24, 8
local EDGE, TOP, FOOTER_H = Style.PANEL_EDGE, 36, 54
local ROW_SHRINK, ICON_SHRINK = 2, Style.ROW_ICON_SHRINK
local NAME_GAP, NOTE_GAP = Style.ICON_NAME_GAP, Style.NOTE_GAP
local BUY_W, BUY_ALL_W = 52, 130
local CLOSE_SIZE = 20
local VENDOR_GAP = 8
local SCROLL_STEP = ROW_H * 3
local RETRY_DELAY = 0.5

local TEXT_TITLE = ns.L("Buy from Vendor")
local TEXT_BUY = ns.L("Buy")
local TEXT_BUY_ALL = ns.L("Buy All (%s)")
local TEXT_ROW = "%dx %s"
local TEXT_ITEM = ns.L("item ")
local TEXT_TOTAL = ns.L("Total: %s")
local TEXT_ONLY = ns.L("only %d/%d, %s")
local TEXT_BUNDLE = ns.L("buys %d, %s")
local TIP_CLOSE, TIP_CLOSE_HELP = ns.L("Close"), ns.L("Keeps this panel closed until another vendor opens.")
local TIP_BUY_HELP = ns.L("Buys this queue shortage from the current vendor.")
local TIP_BUY_ALL_HELP = ns.L("Buys every queue shortage sold by the current vendor.")

local panel, scroll, content, totalText, buyAll
local rows = {}
local dismissed, pending = false, false
local events = CreateFrame("Frame")
local Render

local function On()
    return S.Get("enabled") and S.Get("shoppingList") and S.Get("buyVendor")
end

local function VendorOpen()
    local vendor = _G.MerchantFrame
    return vendor and vendor:IsShown()
end

local function Place()
    if not (panel and _G.MerchantFrame) then return end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", VENDOR_GAP, 0)
end

local function OnRowEnter(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.item)
    GameTooltip:Show()
end

local function Purchase(itemID)
    if pending then return end
    pending = true
    Render()
    if not V.BuyQueueItem(itemID) then
        pending = false
        return Render()
    end
    C_Timer.After(RETRY_DELAY, function()
        pending = false
        Render()
    end)
end

local function PurchaseAll()
    if pending then return end
    pending = true
    Render()
    if not V.BuyQueueAll() then
        pending = false
        return Render()
    end
    C_Timer.After(RETRY_DELAY, function()
        pending = false
        Render()
    end)
end

local function NewRow(index)
    local row = CreateFrame("Frame", nil, content)
    row:SetHeight(ROW_H - ROW_SHRINK)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_H)
    row:SetPoint("TOPRIGHT", 0, -(index - 1) * ROW_H)
    row:EnableMouse(true)
    row.icon = Widgets.Crop(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetSize(ROW_H - ICON_SHRINK, ROW_H - ICON_SHRINK)
    row.icon:SetPoint("LEFT")
    row.buy = ns.Button(row, TEXT_BUY, BUY_W, ROW_H - ROW_SHRINK, function()
        if row.item then Purchase(row.item) end
    end)
    row.buy:SetPoint("RIGHT")
    ns.Tooltip(row.buy, TEXT_BUY, TIP_BUY_HELP)
    row.note = ns.Font(row, Style.FONT_SMALL, nil, T.muted)
    row.note:SetPoint("RIGHT", row.buy, "LEFT", -NOTE_GAP, 0)
    row.note:SetJustifyH("RIGHT")
    row.name = ns.Font(row, Style.FONT, nil)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", NAME_GAP, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -NAME_GAP, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[index] = row
    return row
end

local function ScrollWheel(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * SCROLL_STEP)))
end

local function Dismiss()
    dismissed = true
    panel:Hide()
end

local function Build()
    panel = CreateFrame("Frame", nil, UIParent)
    panel:SetSize(WIDTH, TOP + ROW_H + FOOTER_H + EDGE)
    panel:SetFrameStrata("DIALOG")
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true)
    ns.Solid(panel, "BACKGROUND", T.bg, Style.WINDOW_ALPHA):SetAllPoints()
    ns.Border(panel, Style.BORDER_RGB)
    panel.title = ns.Font(panel, Style.FONT_LARGE, nil, T.accent)
    panel.title:SetPoint("TOPLEFT", EDGE, -11)
    panel.title:SetText(TEXT_TITLE)
    panel.close = ns.Button(panel, "X", CLOSE_SIZE, CLOSE_SIZE, Dismiss)
    panel.close:SetPoint("TOPRIGHT", -EDGE, -8)
    ns.Tooltip(panel.close, TIP_CLOSE, TIP_CLOSE_HELP)
    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", EDGE, -TOP)
    scroll:SetPoint("TOPRIGHT", -EDGE, -TOP)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", ScrollWheel)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - 2 * EDGE, 1)
    scroll:SetScrollChild(content)
    totalText = ns.Font(panel, Style.FONT_SMALL, nil, T.muted)
    totalText:SetPoint("BOTTOMLEFT", EDGE, EDGE + Style.BUTTON_H / 2)
    totalText:SetJustifyH("LEFT")
    totalText:SetWordWrap(false)
    buyAll = ns.Button(panel, TEXT_BUY_ALL:format(""), BUY_ALL_W, Style.BUTTON_H, PurchaseAll)
    buyAll:SetPoint("BOTTOMRIGHT", -EDGE, EDGE)
    ns.Tooltip(buyAll, TEXT_TITLE, TIP_BUY_ALL_HELP)
    totalText:SetPoint("RIGHT", buyAll, "LEFT", -NOTE_GAP, 0)
    panel:Hide()
end

local function Fill(list)
    for index = 1, math.max(#list, #rows) do
        local entry = list[index]
        local row = (entry or rows[index]) and (rows[index] or NewRow(index))
        if entry then
            local name = Shopping.ItemName(entry.itemID) or (TEXT_ITEM .. entry.itemID)
            row.item = entry.itemID
            row.icon:SetTexture(C_Item.GetItemIconByID(entry.itemID))
            row.name:SetText(TEXT_ROW:format(entry.want, name))
            local cost = Text.Short(entry.cost)
            if entry.short then
                row.note:SetText(Style.ALERT_CODE .. TEXT_ONLY:format(entry.count, entry.want, cost) .. "|r")
            elseif entry.count > entry.want then
                row.note:SetText(TEXT_BUNDLE:format(entry.count, cost))
            else
                row.note:SetText(cost)
            end
            Widgets.EnableButton(row.buy, not pending and GetMoney() >= entry.cost)
            row:Show()
        elseif row then
            row.item = nil
            row:Hide()
        end
    end
end

Render = function()
    if not (On() and VendorOpen()) or dismissed then return panel and panel:Hide() end
    local list, total = V.QueueList()
    if #list == 0 then return panel and panel:Hide() end
    if not panel then Build() end
    Fill(list)
    local visible = math.min(#list, MAX_VISIBLE)
    local scrollHeight = visible * ROW_H
    scroll:SetHeight(scrollHeight)
    content:SetHeight(math.max(scrollHeight, #list * ROW_H))
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local range = scroll:GetVerticalScrollRange() or 0
    if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
    panel:SetHeight(TOP + scrollHeight + FOOTER_H + EDGE)
    totalText:SetText(TEXT_TOTAL:format(Text.Short(total)))
    ns.SetButtonText(buyAll, TEXT_BUY_ALL:format(Text.Short(total)))
    Widgets.EnableButton(buyAll, not pending and GetMoney() >= total)
    Place()
    panel:Show()
end

local function OnEvent(_, event)
    if event == "MERCHANT_SHOW" then
        dismissed, pending = false, false
        return C_Timer.After(0, Render)
    end
    if event == "MERCHANT_CLOSED" then
        dismissed, pending = false, false
        if panel then panel:Hide() end
        return
    end
    if event == "BAG_UPDATE_DELAYED" then
        pending = false
        return C_Timer.After(0, Render)
    end
    if pending then return end
    Render()
end

local function Apply()
    events:UnregisterAllEvents()
    if not On() then
        if panel then panel:Hide() end
        return
    end
    events:RegisterEvent("MERCHANT_SHOW")
    events:RegisterEvent("MERCHANT_UPDATE")
    events:RegisterEvent("MERCHANT_CLOSED")
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_MONEY")
    events:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    if VendorOpen() then C_Timer.After(0, Render) end
end

S.OnChange(function(key)
    if key == "enabled" or key == "shoppingList" or key == "buyVendor" then Apply() end
end)
events:SetScript("OnEvent", OnEvent)
Shopping.OnChange(Render)
hooksecurefunc(ns, "Apply", Apply)
Apply()
