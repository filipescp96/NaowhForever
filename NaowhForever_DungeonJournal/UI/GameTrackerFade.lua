-- GameTrackerFade.lua: Hide the Game's Quest Tracker: the game's tracker faded while this setting is on, with EllesmereUI's tracker visibility handed to us meanwhile.
local ns = _G.NaowhForever

local J = ns.Journal
local S = J.Settings
local Tracker = J.QuestTracker

local FADED, SHOWN = 0, 1
local EUI_SUPPRESSOR = "NaowhForeverDungeonJournal"

local gameFaded, gameHooked, keepingFaded, euiSuppressed = false, false, false, false
local events

local function KeepFaded(frame, alpha)
    if not gameFaded or keepingFaded or alpha == FADED then return end
    keepingFaded = true
    frame:SetAlpha(FADED)
    keepingFaded = false
end

local function SuppressEllesmere(on)
    local setSuppressed = _G._EQT_SetSuppressed
    if type(setSuppressed) ~= "function" or euiSuppressed == on then return end
    euiSuppressed = on
    setSuppressed(EUI_SUPPRESSOR, on)
end

local function ShouldFade()
    return S.Get("enabled") and S.Get("hideGameTracker")
end

function Tracker.SyncGameTracker()
    local frame = _G.ObjectiveTrackerFrame
    if not frame then return end
    if ShouldFade() then
        if not gameHooked then
            gameHooked = true
            hooksecurefunc(frame, "Show", KeepFaded)
            hooksecurefunc(frame, "SetAlpha", KeepFaded)
        end
        gameFaded = true
        SuppressEllesmere(true)
        frame:SetAlpha(FADED)
    elseif gameFaded then
        gameFaded = false
        if euiSuppressed then SuppressEllesmere(false) end
        frame:SetAlpha(SHOWN)
    end
end

local function ApplyEvents()
    if not ShouldFade() then
        if events then events:UnregisterAllEvents() end
        Tracker.SyncGameTracker()
        return
    end
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", Tracker.SyncGameTracker)
    end
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    Tracker.SyncGameTracker()
end

local function OnSettingChanged(key)
    if key == "enabled" then
        ApplyEvents()
    elseif key == "hideGameTracker" then
        ApplyEvents()
    end
end

hooksecurefunc(ns, "Apply", ApplyEvents)
S.OnChange(OnSettingChanged)
ApplyEvents()
