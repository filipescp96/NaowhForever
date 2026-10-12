-- FinderRoles.lua: Group Finder Roles, role buttons on the Group Finder that list only players of those roles.
local ns = _G.NaowhForever

local S = ns.QoLSettings

local BUTTON_SIZE = 22
local BUTTON_GAP = 4
local LABEL_GAP = 8
local ROW_DROP = 10
local OFF_ALPHA = 0.4
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local TEXT_TIP = "Show only players who signed up as %s. With no role picked, everyone shows."
local TEXT_GROUPS = "Groups are hidden while a role is picked."
local TEXT_LABEL = "Show only:"

local ROLES = {
    { key = "finderRolesTank", field = "tank", atlas = "groupfinder-icon-role-large-tank", name = "Tank" },
    { key = "finderRolesHealer", field = "healer", atlas = "groupfinder-icon-role-large-heal", name = "Healer" },
    { key = "finderRolesDps", field = "dps", atlas = "groupfinder-icon-role-large-dps", name = "Damage" },
}

local roleKeys = {}
for _, role in ipairs(ROLES) do roleKeys[role.key] = true end

local finder, row
local events = CreateFrame("Frame")

local function On()
    return S.Get("enabled") and S.Get("finderRoles")
end

local function Filtering()
    if not On() then return false end
    for _, role in ipairs(ROLES) do
        if S.Get(role.key) then return true end
    end
    return false
end

local function Wanted(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info then return false end
    if info.hasSelf then return true end
    if info.numMembers ~= 1 then return false end
    local player = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
    local roles = player and player.lfgRoles
    if not roles then return false end
    for _, role in ipairs(ROLES) do
        if S.Get(role.key) and roles[role.field] then return true end
    end
    return false
end

local function FilterResults(frame)
    if not Filtering() then return end
    local results = frame.results
    local kept = 0
    for i = 1, #results do
        local id = results[i]
        results[i] = nil
        if Wanted(id) then
            kept = kept + 1
            results[kept] = id
        end
    end
    frame.totalResults = kept
    frame:UpdateResults()
end

local function Paint(button)
    local picked = S.Get(button.role.key)
    button.icon:SetDesaturated(not picked)
    button.icon:SetAlpha(picked and 1 or OFF_ALPHA)
end

local function Refresh()
    if not row then return end
    for _, button in ipairs(row.buttons) do Paint(button) end
    if finder:IsShown() then finder:UpdateResultList() end
end

local function OnClick(button)
    S.Set(button.role.key, not S.Get(button.role.key))
end

local function OnEnter(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(button.role.name, 1, 1, 1)
    GameTooltip:AddLine(TEXT_TIP:format(button.role.name), nil, nil, nil, true)
    GameTooltip:AddLine(TEXT_GROUPS, nil, nil, nil, true)
    GameTooltip:Show()
end

local function MakeRow()
    row = CreateFrame("Frame", nil, finder)
    row:SetHeight(BUTTON_SIZE)
    row:SetPoint("TOPLEFT", finder.CategoryDropdown, "BOTTOMLEFT", 0, -ROW_DROP)
    row:SetFrameLevel(finder.CategoryDropdown:GetFrameLevel() + 1)
    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("LEFT")
    label:SetText(TEXT_LABEL)
    row.buttons = {}
    for i, role in ipairs(ROLES) do
        local button = CreateFrame("Button", nil, row)
        button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        button:RegisterForClicks("LeftButtonUp")
        button:SetPoint("LEFT", label, "RIGHT", LABEL_GAP + (i - 1) * (BUTTON_SIZE + BUTTON_GAP), 0)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAllPoints()
        button.icon:SetAtlas(role.atlas)
        button:SetHighlightTexture(HIGHLIGHT, "ADD")
        button.role = role
        button:SetScript("OnClick", OnClick)
        button:SetScript("OnEnter", OnEnter)
        button:SetScript("OnLeave", GameTooltip_Hide)
        row.buttons[i] = button
    end
    row:SetWidth(label:GetStringWidth() + LABEL_GAP + #ROLES * (BUTTON_SIZE + BUTTON_GAP))
end

local function HookFinder()
    if finder then return end
    local frame = _G.LFGBrowseFrame
    if not frame or not frame.UpdateResultList then return end
    finder = frame
    hooksecurefunc(finder, "UpdateResultList", FilterResults)
    MakeRow()
end

local function OnEvent()
    HookFinder()
    if finder then
        events:UnregisterEvent("ADDON_LOADED")
        Refresh()
    end
end

events:SetScript("OnEvent", OnEvent)

local function Apply()
    if not On() then
        events:UnregisterAllEvents()
        if row then
            row:Hide()
            if finder:IsShown() then finder:UpdateResultList() end
        end
        return
    end
    HookFinder()
    if not finder then
        events:RegisterEvent("ADDON_LOADED")
        return
    end
    row:Show()
    Refresh()
end

local function OnSettingChanged(key)
    if key == "enabled" or key == "finderRoles" then
        Apply()
    elseif row and roleKeys[key] then
        Refresh()
    end
end

hooksecurefunc(S, "Set", OnSettingChanged)
hooksecurefunc(ns, "Apply", Apply)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

ns.Shared.Settings.Page("QoL/Questing & Group", S):Card({
    id = "finderRoles", name = "Group Finder Roles", order = 45, switch = "finderRoles",
    help = "Tank, Healer and Damage buttons under the Group Finder's Category filter. Click one or more "
        .. "and the list shows only players who signed up for those roles, so looking for a healer "
        .. "shows only healers. Groups are hidden while a role is picked; with none picked, the list "
        .. "is the game's own. Your picks are kept for next time.",
})
