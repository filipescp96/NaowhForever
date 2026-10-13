-- Unit tests for ROI calculation, formatting and configurable colour bands.
local settings = { roiGreyBelow = 10, roiGreenFrom = 30 }

_G.NaowhForever = {
    AuctionScanTime = function() return 1 end,
    Professions = {
        Settings = { Get = function(key) return settings[key] end },
        Recipes = {},
        Vendors = {},
    },
}

dofile("../../NaowhForever_Professions/Prices.lua")

local Prices = _G.NaowhForever.Professions.Prices
assert(Prices.ROI(25, 100) == 25, "ROI should be profit divided by cost")
assert(Prices.ROI(-10, 50) == -20, "negative ROI should be retained for the detail panel")
assert(Prices.ROI(10, 0) == nil, "zero crafting cost has no meaningful ROI")
assert(Prices.ROIBand(-1) == "negative", "negative ROI should be red")
assert(Prices.ROIBand(9.9) == "muted", "ROI below 10% should be grey")
assert(Prices.ROIBand(10) == "yellow", "ROI at 10% should be yellow")
assert(Prices.ROIBand(29.9) == "yellow", "ROI below 30% should remain yellow")
assert(Prices.ROIBand(30) == "green", "ROI at 30% should be green")
assert(Prices.ROIText(12.6) == "(13% ROI)", "ROI text should use a rounded whole percentage")

settings.roiGreyBelow, settings.roiGreenFrom = 20, 50
assert(Prices.ROIBand(19) == "muted", "custom grey threshold should be used")
assert(Prices.ROIBand(20) == "yellow", "custom yellow range should be used")
assert(Prices.ROIBand(50) == "green", "custom green threshold should be used")

settings.roiGreyBelow, settings.roiGreenFrom = 40, 20
assert(Prices.ROIBand(39) == "muted", "grey threshold should remain authoritative")
assert(Prices.ROIBand(40) == "green", "green threshold should not fall below grey")

print("ROI profit tests: PASS")
