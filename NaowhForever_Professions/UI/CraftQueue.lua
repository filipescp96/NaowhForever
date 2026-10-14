-- CraftQueue.lua: the crafting queue docked to Naowh's profession window.
local ns = _G.NaowhForever

local T = ns.THEME

local P = ns.Professions
local S = P.Settings
local Queue = P.CraftQueue
local Shopping = P.Shopping
local Text = P.Text
local Style = P.Style
local Widgets = P.Widgets

local WIDTH = 260
local ROW_H = 20
local ROW_X = 8
local ROW_SHRINK = 2
local ICON_SHRINK = Style.ROW_ICON_SHRINK
local NAME_GAP = Style.ICON_NAME_GAP
local TITLE_X, TITLE_DROP = 10, 10
local LIST_DROP, LIST_BOTTOM = 34, 50
local SCROLLBAR_ROOM = 22
local SCROLL_STEP = ROW_H * 3
local HEAD_X, HEAD_STEP = 10, 18
local SECTION_GAP = 8
local SMALL_BUTTON = 16
local STEP_GAP, MINUS_GAP = 6, 2
local BUTTON_EDGE = 10
local SHOP_W, START_W = 112, 94

local TEXT_TITLE = ns.L("Crafting Queue")
local TEXT_PREREQUISITES = ns.L("Pre-requisite Crafts")
local TEXT_CRAFTS = ns.L("Crafts")
local TEXT_EMPTY = ns.L("Crafts you add appear here. Their missing materials are added to the Shopping List.")
local TEXT_ROW = "%dx %s"
local TEXT_UNKNOWN = "?"
local TEXT_START = ns.L("Start Queue")
local TEXT_RUNNING = ns.L("Crafting...")
local TEXT_NEXT = ns.L("Craft Next")
local TEXT_SHOPPING = ns.L("Shopping List")
local TEXT_MISSING = ns.L("Missing Materials")
local TEXT_HAVE = ns.L("%d / %d")
local TEXT_VENDOR_COST = ns.L("Vendor cost: %s")
local TEXT_VENDOR_UNKNOWN = ns.L("Vendor price unknown")
local TIP_REMOVE, TIP_REMOVE_HELP = ns.L("Remove"), ns.L("Takes this craft and its materials off the queue.")
local TIP_MORE, TIP_MORE_HELP = ns.L("One More"), ns.L("Adds the materials for one more craft.")
local TIP_FEWER, TIP_FEWER_HELP = ns.L("One Fewer"), ns.L("Takes the materials for one craft off the queue.")
local TIP_START_HELP = ns.L("Start Queue prepares the first ready prerequisite or craft. Then click Craft Next "
    .. "once for each prepared batch, as required by Blizzard; entries with missing materials are skipped.")
local TIP_SHOPPING_HELP = ns.L("Opens Naowh's Shopping List, including items and consumables.")

local View = { WIDTH = WIDTH }
P.CraftQueueView = View

local panel, scroll, content, empty, start
local heads = {}
local pools = { prerequisites = {}, crafts = {} }
local sectionEntries = { prerequisites = {}, crafts = {} }
local events

local function On()
    return S.Get("enabled") and S.Get("shoppingList")
end

local function OnRowEnter(self)
    if not self.spell then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, self.spell) then
        GameTooltip:SetSpellByID(self.spell)
    end
    GameTooltip:Show()
end

local function OnMissingEnter(self)
    local entry = self.entry
    if not entry then return end
    local rows, _, _, vendorCost = Queue.Requirements(entry)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(TEXT_MISSING, 1, 1, 1)
    for _, material in ipairs(rows) do
        local color = material.missing > 0 and Style.RED_RGB or T.accent
        local name = material.name .. (material.vendor and ("  " .. Style.VENDOR_ICON) or "")
        GameTooltip:AddDoubleLine(name, TEXT_HAVE:format(material.have, material.need),
            color.r, color.g, color.b, color.r, color.g, color.b)
        if material.vendor and material.missing > 0 then
            local cost = material.vendorPrice and Text.Money(material.vendorPrice * material.missing)
                or TEXT_VENDOR_UNKNOWN
            GameTooltip:AddLine("  " .. (material.vendorPrice and TEXT_VENDOR_COST:format(cost) or cost),
                Style.VENDOR_RGB.r, Style.VENDOR_RGB.g, Style.VENDOR_RGB.b)
        end
    end
    if vendorCost > 0 then
        GameTooltip:AddLine(TEXT_VENDOR_COST:format(Text.Money(vendorCost)),
            Style.VENDOR_RGB.r, Style.VENDOR_RGB.g, Style.VENDOR_RGB.b)
    end
    GameTooltip:Show()
end

local function NewRow(pool, index)
    local row = pool[index]
    if row then return row end
    row = CreateFrame("Frame", nil, content)
    row:SetSize(WIDTH - ROW_X * 2 - SCROLLBAR_ROOM, ROW_H - ROW_SHRINK)
    row:EnableMouse(true)
    row.warning = CreateFrame("Button", nil, row)
    row.warning:SetSize(SMALL_BUTTON, SMALL_BUTTON)
    row.warning:SetPoint("LEFT")
    row.warning.text = ns.Font(row.warning, Style.FONT_HEAD, nil, Style.RED_RGB)
    row.warning.text:SetPoint("CENTER")
    row.warning.text:SetText("!")
    row.warning:SetScript("OnEnter", OnMissingEnter)
    row.warning:SetScript("OnLeave", GameTooltip_Hide)
    row.icon = Widgets.Crop(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetSize(ROW_H - ICON_SHRINK, ROW_H - ICON_SHRINK)
    row.name = ns.Font(row, Style.FONT, nil)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.remove = ns.Button(row, "X", SMALL_BUTTON, SMALL_BUTTON, function()
        local entry = row.entry
        if entry then Queue.Remove(entry.recipeID, entry.prerequisite) end
    end)
    row.remove:SetPoint("RIGHT")
    ns.Tooltip(row.remove, TIP_REMOVE, TIP_REMOVE_HELP)
    row.plus = ns.Button(row, "+", SMALL_BUTTON, SMALL_BUTTON, function()
        local entry = row.entry
        if entry then Queue.Step(entry.recipeID, entry.prerequisite, 1) end
    end)
    row.plus:SetPoint("RIGHT", row.remove, "LEFT", -STEP_GAP, 0)
    ns.Tooltip(row.plus, TIP_MORE, TIP_MORE_HELP)
    row.minus = ns.Button(row, "-", SMALL_BUTTON, SMALL_BUTTON, function()
        local entry = row.entry
        if entry then Queue.Step(entry.recipeID, entry.prerequisite, -1) end
    end)
    row.minus:SetPoint("RIGHT", row.plus, "LEFT", -MINUS_GAP, 0)
    ns.Tooltip(row.minus, TIP_FEWER, TIP_FEWER_HELP)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    pool[index] = row
    return row
end

local function Entries(prerequisite)
    local key = prerequisite and "prerequisites" or "crafts"
    local list = sectionEntries[key]
    wipe(list)
    for _, entry in ipairs(Queue.Ordered()) do
        if entry.prerequisite == prerequisite then list[#list + 1] = entry end
    end
    return key, list
end

local function PlaceSection(prerequisite, y)
    local key, entries = Entries(prerequisite)
    local head, pool = heads[key], pools[key]
    head:SetShown(#entries > 0)
    if #entries > 0 then
        if y < 0 then y = y - SECTION_GAP end
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", HEAD_X, y)
        y = y - HEAD_STEP
    end
    for index = 1, math.max(#entries, #pool) do
        local entry = entries[index]
        local row = (entry or pool[index]) and NewRow(pool, index)
        if entry then
            local _, missing = Queue.Requirements(entry)
            row.entry, row.spell = entry, entry.recipeID
            row.icon:SetTexture(entry.icon or C_Spell.GetSpellTexture(entry.recipeID))
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", missing and row.warning or row,
                missing and "RIGHT" or "LEFT", missing and 2 or 0, 0)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", NAME_GAP, 0)
            row.name:SetPoint("RIGHT", row.minus, "LEFT", -STEP_GAP, 0)
            row.name:SetText(TEXT_ROW:format(entry.count, entry.name or TEXT_UNKNOWN))
            row.warning:SetShown(missing)
            row.warning.entry = entry
            local editing = not Queue.Running()
            Widgets.EnableButton(row.remove, editing)
            Widgets.EnableButton(row.plus, editing)
            Widgets.EnableButton(row.minus, editing and entry.count > 1)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", ROW_X, y)
            row:Show()
            y = y - ROW_H
        elseif row then
            row:Hide()
        end
    end
    return y, #entries
end

function View.Render()
    if not panel then return end
    local y, prerequisites = PlaceSection(true, 0)
    local crafts
    y, crafts = PlaceSection(false, y)
    local count = prerequisites + crafts
    empty:SetShown(count == 0)
    scroll:SetShown(count > 0)
    content:SetHeight(math.max(scroll:GetHeight(), -y + SECTION_GAP))
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    local range = scroll:GetVerticalScrollRange() or 0
    if scroll:GetVerticalScroll() > range then scroll:SetVerticalScroll(range) end
    local active = Queue.Active()
    ns.SetButtonText(start, Queue.Running() and (active and active.started and TEXT_RUNNING or TEXT_NEXT)
        or TEXT_START)
    Widgets.EnableButton(start, count > 0 and (not Queue.Running() or (active and not active.started)))
end

local function ScrollWheel(self, delta)
    local range = self:GetVerticalScrollRange() or 0
    self:SetVerticalScroll(math.max(0, math.min(range, self:GetVerticalScroll() - delta * SCROLL_STEP)))
end

local function BuildHead(key, text)
    local head = ns.Font(content, Style.FONT, nil, Style.GOLD_RGB)
    head:SetText(text)
    heads[key] = head
end

function View.Attach(win)
    if panel then return end
    panel = CreateFrame("Frame", nil, win)
    panel:SetPoint("TOPLEFT", win.mid, "TOPRIGHT", Style.PAD, 0)
    panel:SetPoint("BOTTOMLEFT", win.mid, "BOTTOMRIGHT", Style.PAD, 0)
    panel:SetWidth(WIDTH)
    ns.Solid(panel, "BACKGROUND", T.panel, Style.PANEL_ALPHA):SetAllPoints()
    local title = ns.Font(panel, Style.FONT_HEAD, nil, T.accent)
    title:SetPoint("TOPLEFT", TITLE_X, -TITLE_DROP)
    title:SetText(TEXT_TITLE)
    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", 0, -LIST_DROP)
    scroll:SetPoint("BOTTOMRIGHT", -2, LIST_BOTTOM)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", ScrollWheel)
    content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIDTH - SCROLLBAR_ROOM, 1)
    scroll:SetScrollChild(content)
    BuildHead("prerequisites", TEXT_PREREQUISITES)
    BuildHead("crafts", TEXT_CRAFTS)
    empty = ns.Font(panel, Style.FONT, nil, T.muted)
    empty:SetPoint("TOPLEFT", TITLE_X, -LIST_DROP)
    empty:SetWidth(WIDTH - TITLE_X * 2)
    empty:SetJustifyH("LEFT")
    empty:SetWordWrap(true)
    empty:SetText(TEXT_EMPTY)
    start = ns.Button(panel, TEXT_START, START_W, Style.BUTTON_H, Queue.Click)
    start:SetPoint("BOTTOMRIGHT", -BUTTON_EDGE, BUTTON_EDGE)
    ns.Tooltip(start, TEXT_START, TIP_START_HELP)
    local shopping = ns.Button(panel, TEXT_SHOPPING, SHOP_W, Style.BUTTON_H, ns.ToggleShoppingList)
    shopping:SetPoint("BOTTOMLEFT", BUTTON_EDGE, BUTTON_EDGE)
    ns.Tooltip(shopping, TEXT_SHOPPING, TIP_SHOPPING_HELP)
    events = CreateFrame("Frame")
    events:SetScript("OnEvent", View.Render)
    panel:HookScript("OnShow", function()
        events:RegisterEvent("BAG_UPDATE_DELAYED")
        View.Render()
    end)
    panel:HookScript("OnHide", function() events:UnregisterAllEvents() end)
    panel:Hide()
end

function View.SetShown(shown)
    if panel then panel:SetShown(shown and On()) end
end

Queue.Render = function()
    if P.List and P.List.UpdateShoppingMarkers then P.List.UpdateShoppingMarkers() end
    View.Render()
end

Shopping.OnChange(function()
    if P.Detail and P.Detail.UpdateShoppingCount then P.Detail.UpdateShoppingCount() end
    if P.List and P.List.UpdateShoppingMarkers then P.List.UpdateShoppingMarkers() end
end)
