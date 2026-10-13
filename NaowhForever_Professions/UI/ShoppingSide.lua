-- ShoppingSide.lua: the docked crafting queue, standalone shopping list, and recipe queue controls.
local ns = _G.NaowhForever

local T = ns.THEME

local P = ns.Professions
local S = P.Settings
local C = P.C
local Shopping = P.Shopping
local Queue = P.CraftQueue
local Text = P.Text
local Style = P.Style
local Widgets = P.Widgets

local SIDE_W, SIDE_ROW_H = 260, 20
local SIDE_GAP = 8
local ROW_SHRINK = 2
local ICON_SHRINK = Style.ROW_ICON_SHRINK
local NAME_GAP = Style.ICON_NAME_GAP
local TITLE_X, TITLE_DROP = 10, 10
local HINT_DROP = 36
local HINT_ROOM = 20
local HINT_SPACING = 2
local LIST_TOP = -4
local LIST_DROP, LIST_BOTTOM = 34, 50
local SCROLLBAR_ROOM = 22
local SCROLL_STEP = SIDE_ROW_H * 3
local HEAD_X, HEAD_STEP = 10, 18
local SECTION_GAP = 8
local ROW_X = 8
local TOTAL_X, TOTAL_BOTTOM, TOTAL_RIGHT = 10, 16, 100
local CLEAR_W, CLEAR_EDGE = 80, 10
local SHOP_OPEN_W = 112
local SHOP_MIN_H, SHOP_MAX_H = 160, 420
local SHOP_CLOSE, SHOP_CLOSE_EDGE = 20, 7
local SMALL_BUTTON = 16
local STEP_GAP, MINUS_GAP = 6, 2
local MAKE_W, KEEP_W = 40, 34
local ADD_QUEUE_W = 142
local ADD_DROP = 4
local ADD_OVERHANG = 4
local TEXT_TITLE = ns.L("Shopping List")
local TEXT_HINT = ns.L("Choose a recipe, set how many crafts and click Add to Crafting Queue: "
    .. "its missing auction-house materials land here, ready to check and buy.")
local TEXT_CRAFTS, TEXT_MATERIALS, TEXT_MADE = ns.L("Crafts"), ns.L("Materials"), ns.L("Make First")
local TEXT_CLEAR = ns.L("Clear")
local TEXT_ROW = "%dx %s"
local TEXT_UNKNOWN = "?"
local TEXT_ITEM = ns.L("item ")
local TEXT_NO_PRICE = ns.L("no price")
local TEXT_ABOUT = "~"
local TEXT_PARTS_BOUGHT = ns.L("parts bought")
local TEXT_SAVES = ns.L("saves ~")
local TEXT_NO_AH_PRICE = ns.L("no AH price")
local TEXT_UNPRICED = ns.L("unpriced")
local TEXT_QUEUE_TITLE = ns.L("Crafting Queue")
local TEXT_OPEN_SHOP = ns.L("Shopping List")
local TEXT_PREREQUISITES = ns.L("Pre-requisite Crafts")
local TEXT_QUEUE_CRAFTS = ns.L("Crafts")
local TEXT_QUEUE_EMPTY = ns.L("Crafts with purchased materials or crafts you add manually appear here.")
local TEXT_ADD_QUEUE = ns.L("Add to Crafting Queue")
local TEXT_START_QUEUE = ns.L("Start Queue")
local TEXT_RUNNING = ns.L("Crafting...")
local TEXT_CRAFT_NEXT = ns.L("Craft Next")
local TEXT_VENDOR_COST = ns.L("Vendor cost: %s")
local TEXT_VENDOR_UNKNOWN = ns.L("Vendor price unknown")
local TEXT_HAVE = ns.L("%d / %d")
local TEXT_MAKE, TEXT_BUY = ns.L("Make"), ns.L("Buy")
local TIP_CLEAR_HELP = ns.L("Empties the shopping list.")
local TIP_REMOVE, TIP_REMOVE_HELP = ns.L("Remove"), ns.L("Takes this craft and its materials off the list.")
local TIP_MORE, TIP_MORE_HELP = ns.L("One More"), ns.L("Adds the materials for one more craft.")
local TIP_FEWER, TIP_FEWER_HELP = ns.L("One Fewer"), ns.L("Takes the materials for one craft off the list.")
local TIP_MAKE, TIP_MAKE_HELP = ns.L("Make It"), ns.L("Buys its cheaper parts instead, to make it yourself.")
local TIP_KEEP, TIP_KEEP_HELP = ns.L("Buy It"), ns.L("Buys it as it is instead of its parts.")
local TIP_CRAFTS, TIP_CRAFTS_HELP = ns.L("Crafts"), ns.L("How many crafts Add to Crafting Queue adds.")
local TIP_ADD_QUEUE = ns.L("Add to Crafting Queue")
local TIP_ADD_QUEUE_HELP = ns.L("Adds this recipe and its cheaper prerequisite crafts to the crafting queue, "
    .. "then puts its missing auction-house materials on the shopping list.")
local TIP_QUEUE_MISSING = ns.L("Missing Materials")
local TIP_START_QUEUE_HELP = ns.L("Start Queue prepares the first ready prerequisite or craft. "
    .. "Then click Craft Next once for each prepared batch, as required by Blizzard; entries with missing materials are skipped.")
local TIP_OPEN_SHOP_HELP = ns.L("Shows the standalone shopping list window.")

local side
local crafts, craftPool, madeList, madePool = {}, {}, {}, {}
local queueEntries = { prerequisites = {}, crafts = {} }
local addRow, addRecipe

local function On()
    return S.Get("enabled") and S.Get("shoppingList")
end

local function ByCraftName(a, b)
    return (a.craft.name or "") < (b.craft.name or "")
end

local function OnRowEnter(self)
    if not (self.item or self.spell) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.item then
        GameTooltip:SetItemByID(self.item)
    elseif not pcall(GameTooltip.SetRecipeResultItem, GameTooltip, self.spell) then
        GameTooltip:SetSpellByID(self.spell)
    end
    GameTooltip:Show()
end

local function SideRow(pool, i, content)
    local row = pool[i]
    if row then return row end
    content = content or side.content
    row = CreateFrame("Frame", nil, content)
    row:SetSize(content:GetWidth() - ROW_X * 2, SIDE_ROW_H - ROW_SHRINK)
    row:EnableMouse(true)
    row.icon = Widgets.Crop(row:CreateTexture(nil, "ARTWORK"))
    row.icon:SetSize(SIDE_ROW_H - ICON_SHRINK, SIDE_ROW_H - ICON_SHRINK)
    row.icon:SetPoint("LEFT")
    row.note = ns.Font(row, Style.FONT_SMALL, nil, T.muted)
    row.note:SetJustifyH("RIGHT")
    row.name = ns.Font(row, Style.FONT, nil)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", NAME_GAP, 0)
    row.name:SetPoint("RIGHT", row.note, "LEFT", -NAME_GAP, 0)
    row:SetScript("OnEnter", OnRowEnter)
    row:SetScript("OnLeave", GameTooltip_Hide)
    pool[i] = row
    return row
end

local function Head(text)
    local head = ns.Font(side.content, Style.FONT, nil, Style.GOLD_RGB)
    head:SetText(text)
    return head
end

local function ScrollWheel(scroll, delta)
    local range = scroll:GetVerticalScrollRange() or 0
    local value = math.max(0, math.min(range, scroll:GetVerticalScroll() - delta * SCROLL_STEP))
    scroll:SetVerticalScroll(value)
end

local function ShowShop()
    if not (side and side.shop) then return end
    side.shop.dismissed = nil
    side.shop:Show()
end

local function HideShop()
    if not (side and side.shop) then return end
    side.shop.dismissed = true
    side.shop:Hide()
end

local function OnShopDragStart(self)
    if InCombatLockdown and InCombatLockdown() then return end
    local x, y = self:GetLeft(), self:GetTop()
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    self:StartMoving()
end

local function OnShopDragStop(self)
    self:StopMovingOrSizing()
end

local function BuildSide(win)
    side = CreateFrame("Frame", nil, win.mid)
    side:SetPoint("TOPLEFT", win.mid, "TOPRIGHT", SIDE_GAP, 0)
    side:SetPoint("BOTTOMLEFT", win.mid, "BOTTOMRIGHT", SIDE_GAP, 0)
    side:SetWidth(SIDE_W)
    local shop = CreateFrame("Frame", nil, UIParent)
    shop:SetSize(SIDE_W, SHOP_MIN_H)
    shop:SetPoint("TOPLEFT", side, "TOPRIGHT", SIDE_GAP, 0)
    shop:SetFrameStrata("DIALOG")
    shop:SetClampedToScreen(true)
    shop:SetMovable(true)
    shop:EnableMouse(true)
    shop:RegisterForDrag("LeftButton")
    shop:SetScript("OnDragStart", OnShopDragStart)
    shop:SetScript("OnDragStop", OnShopDragStop)
    ns.Solid(shop, "BACKGROUND", T.bg, Style.WINDOW_ALPHA):SetAllPoints()
    ns.Border(shop, Style.BORDER_RGB)
    side.shop = shop
    side.title = ns.Font(shop, Style.FONT_HEAD, nil, T.accent)
    side.title:SetPoint("TOPLEFT", TITLE_X, -TITLE_DROP)
    side.title:SetText(TEXT_TITLE)
    shop.close = ns.Button(shop, "X", SHOP_CLOSE, SHOP_CLOSE, HideShop)
    shop.close:SetPoint("TOPRIGHT", -SHOP_CLOSE_EDGE, -SHOP_CLOSE_EDGE)

    -- Intentionally use a bare ScrollFrame. Blizzard's scrollbar template is wider than
    -- this compact Naowh side panel and places its arrows/thumb outside the window.
    side.scroll = CreateFrame("ScrollFrame", nil, shop)
    side.scroll:SetPoint("TOPLEFT", 0, -LIST_DROP)
    side.scroll:SetPoint("BOTTOMRIGHT", -2, LIST_BOTTOM)
    side.scroll:EnableMouseWheel(true)
    side.scroll:SetScript("OnMouseWheel", ScrollWheel)
    side.content = CreateFrame("Frame", nil, side.scroll)
    side.content:SetSize(SIDE_W - SCROLLBAR_ROOM, 1)
    side.scroll:SetScrollChild(side.content)

    side.hint = ns.Font(shop, Style.FONT, nil, T.muted)
    side.hint:SetPoint("TOPLEFT", TITLE_X, -HINT_DROP)
    side.hint:SetWidth(SIDE_W - HINT_ROOM)
    side.hint:SetJustifyH("LEFT")
    side.hint:SetWordWrap(true)
    side.hint:SetSpacing(HINT_SPACING)
    side.hint:SetText(TEXT_HINT)
    side.craftsHead = Head(TEXT_CRAFTS)
    side.materialsHead = Head(TEXT_MATERIALS)
    side.madeHead = Head(TEXT_MADE)
    side.crafts, side.materials, side.made = {}, {}, {}
    side.total = ns.Font(shop, Style.FONT, nil)
    side.total:SetPoint("BOTTOMLEFT", TOTAL_X, TOTAL_BOTTOM)
    side.total:SetPoint("RIGHT", -TOTAL_RIGHT, 0)
    side.total:SetJustifyH("LEFT")
    side.total:SetWordWrap(true)
    side.clear = ns.Button(shop, TEXT_CLEAR, CLEAR_W, Style.BUTTON_H, Shopping.Clear)
    side.clear:SetPoint("BOTTOMRIGHT", -CLEAR_EDGE, CLEAR_EDGE)
    ns.Tooltip(side.clear, TEXT_CLEAR, TIP_CLEAR_HELP)

    local queue = CreateFrame("Frame", nil, side)
    queue:SetAllPoints()
    ns.Solid(queue, "BACKGROUND", T.panel, Style.PANEL_ALPHA):SetAllPoints()
    queue.title = ns.Font(queue, Style.FONT_HEAD, nil, T.accent)
    queue.title:SetPoint("TOPLEFT", TITLE_X, -TITLE_DROP)
    queue.title:SetText(TEXT_QUEUE_TITLE)
    queue.scroll = CreateFrame("ScrollFrame", nil, queue)
    queue.scroll:SetPoint("TOPLEFT", 0, -LIST_DROP)
    queue.scroll:SetPoint("BOTTOMRIGHT", -2, LIST_BOTTOM)
    queue.scroll:EnableMouseWheel(true)
    queue.scroll:SetScript("OnMouseWheel", ScrollWheel)
    queue.content = CreateFrame("Frame", nil, queue.scroll)
    queue.content:SetSize(SIDE_W - SCROLLBAR_ROOM, 1)
    queue.scroll:SetScrollChild(queue.content)
    queue.prereqHead = ns.Font(queue.content, Style.FONT, nil, Style.GOLD_RGB)
    queue.prereqHead:SetText(TEXT_PREREQUISITES)
    queue.craftsHead = ns.Font(queue.content, Style.FONT, nil, Style.GOLD_RGB)
    queue.craftsHead:SetText(TEXT_QUEUE_CRAFTS)
    queue.prerequisites, queue.crafts = {}, {}
    queue.empty = ns.Font(queue, Style.FONT, nil, T.muted)
    queue.empty:SetPoint("TOPLEFT", TITLE_X, -HINT_DROP)
    queue.empty:SetWidth(SIDE_W - HINT_ROOM)
    queue.empty:SetJustifyH("LEFT")
    queue.empty:SetWordWrap(true)
    queue.empty:SetSpacing(HINT_SPACING)
    queue.empty:SetText(TEXT_QUEUE_EMPTY)
    queue.start = ns.Button(queue, TEXT_START_QUEUE, 94, Style.BUTTON_H, Queue.Click)
    queue.start:SetPoint("BOTTOMRIGHT", -CLEAR_EDGE, CLEAR_EDGE)
    ns.Tooltip(queue.start, TEXT_START_QUEUE, TIP_START_QUEUE_HELP)
    queue.shop = ns.Button(queue, TEXT_OPEN_SHOP, SHOP_OPEN_W, Style.BUTTON_H, ShowShop)
    queue.shop:SetPoint("BOTTOMLEFT", CLEAR_EDGE, CLEAR_EDGE)
    ns.Tooltip(queue.shop, TEXT_TITLE, TIP_OPEN_SHOP_HELP)
    side.queue = queue
    shop:Hide()
    side:Hide()
end

local function PlaceHead(head, y)
    head:ClearAllPoints()
    head:SetPoint("TOPLEFT", HEAD_X, y)
    return y - HEAD_STEP
end

local function CraftButtons(row)
    row.remove = ns.Button(row, "X", SMALL_BUTTON, SMALL_BUTTON, function()
        if row.recipeID then Shopping.Remove(row.recipeID) end
    end)
    row.remove:SetPoint("RIGHT")
    ns.Tooltip(row.remove, TIP_REMOVE, TIP_REMOVE_HELP)
    row.plus = ns.Button(row, "+", SMALL_BUTTON, SMALL_BUTTON, function() Shopping.Step(row.recipeID, 1) end)
    row.plus:SetPoint("RIGHT", row.remove, "LEFT", -STEP_GAP, 0)
    ns.Tooltip(row.plus, TIP_MORE, TIP_MORE_HELP)
    row.minus = ns.Button(row, "-", SMALL_BUTTON, SMALL_BUTTON, function() Shopping.Step(row.recipeID, -1) end)
    row.minus:SetPoint("RIGHT", row.plus, "LEFT", -MINUS_GAP, 0)
    ns.Tooltip(row.minus, TIP_FEWER, TIP_FEWER_HELP)
    row.note:SetPoint("RIGHT", row.minus, "LEFT", -STEP_GAP, 0)
end

local function PlaceRow(row, y)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", ROW_X, y)
    row:Show()
    return y - SIDE_ROW_H
end

local function SortedCrafts()
    local n = 0
    for recipeID, craft in pairs(Shopping.List()) do
        n = n + 1
        local e = craftPool[n] or {}
        craftPool[n] = e
        e.id, e.craft = recipeID, craft
        crafts[n] = e
    end
    for i = n + 1, #crafts do crafts[i] = nil end
    table.sort(crafts, ByCraftName)
    return crafts
end

local function DrawCrafts(y)
    if #crafts > 0 then y = PlaceHead(side.craftsHead, y) end
    for i = 1, math.max(#crafts, #side.crafts) do
        local e = crafts[i]
        local row = (e or side.crafts[i]) and SideRow(side.crafts, i)
        if row and e then
            if not row.remove then CraftButtons(row) end
            Widgets.EnableButton(row.minus, e.craft.count > 1)
            row.recipeID, row.spell = e.id, e.id
            row.icon:SetTexture(e.craft.icon or C_Spell.GetSpellTexture(e.id))
            row.name:SetText(TEXT_ROW:format(e.craft.count, e.craft.name or TEXT_UNKNOWN))
            row.note:SetText("")
            y = PlaceRow(row, y)
        elseif row then
            row:Hide()
        end
    end
    return y
end

local function MakeButton(row)
    row.make = ns.Button(row, TEXT_MAKE, MAKE_W, SMALL_BUTTON, function()
        if row.item then
            Shopping.Keep()[row.item] = nil
            Shopping.Redraw()
        end
    end)
    row.make:SetPoint("RIGHT")
    ns.Tooltip(row.make, TIP_MAKE, TIP_MAKE_HELP)
end

local function FillMaterial(row, m, plan)
    local price = Shopping.BuyPrice(m.item)
    local make = false
    if Shopping.Keep()[m.item] then make = select(2, Shopping.Cheapest(m.item, plan, 0, true)) end
    if make and not row.make then MakeButton(row) end
    if row.make then row.make:SetShown(make and true or false) end
    row.note:ClearAllPoints()
    if make then row.note:SetPoint("RIGHT", row.make, "LEFT", -STEP_GAP, 0) else row.note:SetPoint("RIGHT") end
    row.item = m.item
    row.icon:SetTexture(C_Item.GetItemIconByID(m.item))
    row.name:SetText(TEXT_ROW:format(m.qty, Shopping.ItemName(m.item) or (TEXT_ITEM .. m.item)))
    row.note:SetText(price and (TEXT_ABOUT .. Text.Short(price * m.qty)) or TEXT_NO_PRICE)
end

local function DrawMaterials(materials, plan, y)
    if #materials > 0 then y = PlaceHead(side.materialsHead, y - SECTION_GAP) end
    for i = 1, math.max(#materials, #side.materials) do
        local m = materials[i]
        local row = (m or side.materials[i]) and SideRow(side.materials, i)
        if m then
            FillMaterial(row, m, plan)
            y = PlaceRow(row, y)
        elseif row then
            row:Hide()
        end
    end
    return y
end

local function SortedMade(made)
    local n = 0
    for item, qty in pairs(made) do
        n = n + 1
        local e = madePool[n] or {}
        madePool[n] = e
        e.item, e.qty, e.name = item, qty, Shopping.ItemName(item) or ""
        madeList[n] = e
    end
    for i = n + 1, #madeList do madeList[i] = nil end
    table.sort(madeList, Shopping.ByName)
    return madeList
end

local function KeepButton(row)
    row.keep = ns.Button(row, TEXT_BUY, KEEP_W, SMALL_BUTTON, function()
        if row.item then
            Shopping.Keep()[row.item] = true
            Shopping.Redraw()
        end
    end)
    row.keep:SetPoint("RIGHT")
    ns.Tooltip(row.keep, TIP_KEEP, TIP_KEEP_HELP)
    row.note:SetPoint("RIGHT", row.keep, "LEFT", -STEP_GAP, 0)
end

local function FillMade(row, e, plan)
    if not row.keep then KeepButton(row) end
    local planned = plan.planned[e.item]
    row.keep:SetShown(planned and true or false)
    row.note:SetPoint("RIGHT", planned and row.keep or row, planned and "LEFT" or "RIGHT", planned and -STEP_GAP or 0, 0)
    local saves = plan.saves[e.item]
    row.item = e.item
    row.icon:SetTexture(C_Item.GetItemIconByID(e.item))
    row.name:SetText(TEXT_ROW:format(e.qty, Shopping.ItemName(e.item) or (TEXT_ITEM .. e.item)))
    if not planned then
        row.note:SetText(TEXT_PARTS_BOUGHT)
    else
        row.note:SetText(saves and (TEXT_SAVES .. Text.Short(saves)) or TEXT_NO_AH_PRICE)
    end
end

local function DrawMade(made, plan, y)
    local makes = SortedMade(made)
    side.madeHead:SetShown(#makes > 0)
    if #makes > 0 then y = PlaceHead(side.madeHead, y - SECTION_GAP) end
    for i = 1, math.max(#makes, #side.made) do
        local e = makes[i]
        local row = (e or side.made[i]) and SideRow(side.made, i)
        if e then
            FillMade(row, e, plan)
            y = PlaceRow(row, y)
        elseif row then
            row:Hide()
        end
    end
    return y
end

local function OnQueueMissingEnter(self)
    local entry = self.entry
    if not entry then return end
    local rows, _, _, vendorCost = Queue.Requirements(entry)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(TIP_QUEUE_MISSING, 1, 1, 1)
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

local function QueueButtons(row)
    row.remove = ns.Button(row, "X", SMALL_BUTTON, SMALL_BUTTON, function()
        if row.entry then Queue.Remove(row.entry.recipeID, row.entry.prerequisite) end
    end)
    row.remove:SetPoint("RIGHT")
    ns.Tooltip(row.remove, TIP_REMOVE, TIP_REMOVE_HELP)
    row.plus = ns.Button(row, "+", SMALL_BUTTON, SMALL_BUTTON, function()
        if row.entry then Queue.Step(row.entry.recipeID, row.entry.prerequisite, 1) end
    end)
    row.plus:SetPoint("RIGHT", row.remove, "LEFT", -STEP_GAP, 0)
    ns.Tooltip(row.plus, TIP_MORE, TIP_MORE_HELP)
    row.minus = ns.Button(row, "-", SMALL_BUTTON, SMALL_BUTTON, function()
        if row.entry then Queue.Step(row.entry.recipeID, row.entry.prerequisite, -1) end
    end)
    row.minus:SetPoint("RIGHT", row.plus, "LEFT", -MINUS_GAP, 0)
    ns.Tooltip(row.minus, TIP_FEWER, TIP_FEWER_HELP)
    row.warning = CreateFrame("Button", nil, row)
    row.warning:SetSize(SMALL_BUTTON, SMALL_BUTTON)
    row.warning:SetPoint("LEFT")
    row.warning.text = ns.Font(row.warning, Style.FONT_HEAD, nil, Style.RED_RGB)
    row.warning.text:SetPoint("CENTER")
    row.warning.text:SetText("!")
    row.warning:SetScript("OnEnter", OnQueueMissingEnter)
    row.warning:SetScript("OnLeave", GameTooltip_Hide)
    row.note:Hide()
end

local function QueueSectionEntries(prerequisite)
    local key = prerequisite and "prerequisites" or "crafts"
    local list = queueEntries[key]
    wipe(list)
    for _, entry in ipairs(Queue.Ordered()) do
        if entry.prerequisite == prerequisite then list[#list + 1] = entry end
    end
    return list
end

local function DrawQueueSection(q, prerequisite, y)
    local entries = QueueSectionEntries(prerequisite)
    local head = prerequisite and q.prereqHead or q.craftsHead
    local pool = prerequisite and q.prerequisites or q.crafts
    head:SetShown(#entries > 0)
    if #entries > 0 then
        head:ClearAllPoints()
        head:SetPoint("TOPLEFT", HEAD_X, y - (y < LIST_TOP and SECTION_GAP or 0))
        y = y - (y < LIST_TOP and SECTION_GAP or 0) - HEAD_STEP
    end
    for i = 1, math.max(#entries, #pool) do
        local entry = entries[i]
        local row = (entry or pool[i]) and SideRow(pool, i, q.content)
        if row and entry then
            if not row.remove then QueueButtons(row) end
            local _, missing = Queue.Requirements(entry)
            row.entry, row.spell = entry, entry.recipeID
            row.item = nil
            row.icon:SetTexture(entry.icon or C_Spell.GetSpellTexture(entry.recipeID))
            row.name:SetText(TEXT_ROW:format(entry.count, entry.name or TEXT_UNKNOWN))
            row.icon:ClearAllPoints()
            row.icon:SetPoint("LEFT", missing and row.warning or row,
                missing and "RIGHT" or "LEFT", missing and 2 or 0, 0)
            row.name:ClearAllPoints()
            row.name:SetPoint("LEFT", row.icon, "RIGHT", NAME_GAP, 0)
            row.name:SetPoint("RIGHT", row.minus, "LEFT", -STEP_GAP, 0)
            row.warning:SetShown(missing)
            row.warning.entry = entry
            local editing = not Queue.Running()
            Widgets.EnableButton(row.remove, editing)
            Widgets.EnableButton(row.plus, editing)
            Widgets.EnableButton(row.minus, editing and entry.count > 1)
            y = PlaceRow(row, y)
        elseif row then
            row:Hide()
        end
    end
    return y, #entries
end

local function RenderQueue()
    if not (side and side.queue) then return end
    local q = side.queue
    local y, prerequisites = DrawQueueSection(q, true, LIST_TOP)
    local craftsCount
    y, craftsCount = DrawQueueSection(q, false, y)
    local count = prerequisites + craftsCount
    q.empty:SetShown(count == 0)
    q.scroll:SetShown(count > 0)
    q.content:SetHeight(math.max(q.scroll:GetHeight(), -y + SECTION_GAP))
    if q.scroll.UpdateScrollChildRect then q.scroll:UpdateScrollChildRect() end
    local range = q.scroll:GetVerticalScrollRange() or 0
    if q.scroll:GetVerticalScroll() > range then q.scroll:SetVerticalScroll(range) end
    local active = Queue.Active()
    ns.SetButtonText(q.start, Queue.Running() and (active and active.started and TEXT_RUNNING or TEXT_CRAFT_NEXT)
        or TEXT_START_QUEUE)
    Widgets.EnableButton(q.start, count > 0 and (not Queue.Running() or (active and not active.started)))
end

local function RenderSide()
    if not side then return end
    if P.Detail and P.Detail.UpdateShoppingCount then P.Detail.UpdateShoppingCount() end
    if P.List and P.List.UpdateShoppingMarkers then P.List.UpdateShoppingMarkers() end
    local api = ns.ProfWindowAPI
    if not On() then
        side.shop:Hide()
        return side:Hide()
    end
    RenderQueue()
    if api and api.Linked() then return side:Hide() end
    local materials, made, plan = Shopping.Materials()
    SortedCrafts()
    side.hint:SetShown(#crafts == 0)
    side.craftsHead:SetShown(#crafts > 0)
    side.materialsHead:SetShown(#materials > 0)
    local y = DrawCrafts(LIST_TOP)
    y = DrawMaterials(materials, plan, y)
    y = DrawMade(made, plan, y)
    local hasRows = #crafts > 0 or #materials > 0 or #madeList > 0
    side.scroll:SetShown(hasRows)
    local contentHeight = -y + SECTION_GAP
    side.shop:SetHeight(math.min(SHOP_MAX_H, math.max(SHOP_MIN_H,
        LIST_DROP + contentHeight + LIST_BOTTOM)))
    side.content:SetHeight(math.max(side.scroll:GetHeight(), contentHeight))
    if side.scroll.UpdateScrollChildRect then side.scroll:UpdateScrollChildRect() end
    local range = side.scroll:GetVerticalScrollRange() or 0
    if side.scroll:GetVerticalScroll() > range then side.scroll:SetVerticalScroll(range) end
    side.total:SetText(#materials > 0 and Shopping.Estimate(materials, TEXT_UNPRICED) or "")
    side.clear:SetShown(#crafts > 0)
    side:Show()
    if not side.shop.dismissed then side.shop:Show() end
end

local function AddCrafts()
    return math.max(1, tonumber(addRow and addRow.qty:GetText() or "") or 1)
end

local function OnQueueAdd()
    local info = ns.ProfWindowAPI.SelectedInfo()
    if info then
        Queue.AddWithShopping(info, AddCrafts())
        ShowShop()
    end
end

function ns.ShoppingListWide()
    return On() and true or false
end

function ns.ShoppingListAttach(win)
    BuildSide(win)
    local row = CreateFrame("Frame", nil, win.detail)
    row:SetSize(Style.PANE_INNER_W - 8, Style.BUTTON_H)
    row:Hide()
    addRow = row
    row.queue = ns.Button(row, TEXT_ADD_QUEUE, ADD_QUEUE_W, Style.BUTTON_H, OnQueueAdd)
    row.queue:SetPoint("RIGHT")
    ns.Tooltip(row.queue, TIP_ADD_QUEUE, TIP_ADD_QUEUE_HELP)
    local qty = Widgets.QtyBox(row)
    row.qty = qty
    local plus = ns.Button(row, "+", Style.STEP_W, Style.BUTTON_H, function()
        qty:SetText(tostring(math.min(C.MAX_CRAFTS, AddCrafts() + 1)))
    end)
    row.plus = plus
    plus:SetPoint("RIGHT", row.queue, "LEFT", -Style.QTY_GAP, 0)
    qty:SetPoint("RIGHT", plus, "LEFT", -Style.STEP_GAP, 0)
    local minus = ns.Button(row, "-", Style.STEP_W, Style.BUTTON_H, function()
        qty:SetText(tostring(math.max(1, AddCrafts() - 1)))
    end)
    minus:SetPoint("RIGHT", qty, "LEFT", -Style.STEP_GAP, 0)
    ns.Tooltip(qty, TIP_CRAFTS, TIP_CRAFTS_HELP)
end

function ns.ShoppingListRender(info, last)
    if not info then RenderSide() end
    if not addRow then return end
    if not (On() and info and last) then return addRow:Hide() end
    if info.recipeID ~= addRecipe then
        addRecipe = info.recipeID
        addRow.qty:SetText("1")
    end
    local buyRow = addRow:GetParent().buyRow
    addRow:ClearAllPoints()
    if buyRow and buyRow:IsShown() then
        addRow:SetPoint("TOPRIGHT", buyRow, "BOTTOMRIGHT", 0, -ADD_DROP)
    else
        addRow:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", ADD_OVERHANG, -ADD_DROP)
    end
    addRow:Show()
end

function Shopping.HideAdd()
    if addRow then addRow:Hide() end
end

Shopping.RenderSide = RenderSide
Queue.Render = function()
    if P.List and P.List.UpdateShoppingMarkers then P.List.UpdateShoppingMarkers() end
    RenderQueue()
end
