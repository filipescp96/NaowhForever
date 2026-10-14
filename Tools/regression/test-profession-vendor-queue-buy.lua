-- Queue vendor-buy coverage: current-merchant filtering, bundles, limited stock, money checks and purchases.
local wanted = {
    { item = 4000, qty = 7 },
    { item = 4001, qty = 3 },
    { item = 4002, qty = 4 },
}
local merchantItems = {
    { item = 4000, price = 50, stack = 5, available = -1 },
    { item = 4002, price = 20, stack = 1, available = 2 },
}
local bought, printed = {}, {}
local money = 1000

local settings = { enabled = true, vendorMaterials = false, craftProfit = false, buyVendor = false }
local S = {}
function S.Get(key) return settings[key] end
function S.OnChange() end

local ns = {
    L = function(text) return text end,
    Print = function(text) printed[#printed + 1] = text end,
    Apply = function() end,
    AccountSettings = function() return {} end,
    ProfWindowAPI = {},
    Professions = {
        Settings = S,
        On = function() return false end,
        VendorReagents = {},
        Text = { Money = tostring },
        Recipes = {
            Link = function(id) return "Item " .. id end,
            Owned = function() return {} end,
            Reagents = function() return {} end,
            ItemCount = function() return 0 end,
        },
        CraftQueue = { VendorMaterials = function() return wanted end },
    },
}
_G.NaowhForever = ns

C_MerchantFrame = {
    GetItemInfo = function(index)
        local item = merchantItems[index]
        return item and { price = item.price, stackCount = item.stack, numAvailable = item.available,
            hasExtendedCost = false }
    end,
}
function GetMerchantNumItems() return #merchantItems end
function GetMerchantItemID(index) return merchantItems[index] and merchantItems[index].item end
function GetMerchantItemMaxStack() return 99 end
function GetMoney() return money end
function BuyMerchantItem(index, count) bought[#bought + 1] = { index = index, count = count } end
function hooksecurefunc() end

dofile("NaowhForever_Professions/Vendors.lua")
local vendors = assert(ns.Professions.Vendors)

local list, total = vendors.QueueList()
assert(#list == 2, "queue list did not keep only materials sold by the current vendor")
assert(list[1].itemID == 4000 and list[1].want == 7 and list[1].count == 10 and list[1].cost == 100,
    "vendor bundle quantity or cost was wrong")
assert(list[1].short == false, "unlimited vendor stock was marked short")
assert(list[2].itemID == 4002 and list[2].count == 2 and list[2].short == true,
    "limited vendor stock was not capped and marked short")
assert(total == 140, "vendor queue total was wrong")

assert(vendors.BuyQueueItem(4000) == true, "single queue vendor purchase failed")
assert(#bought == 1 and bought[1].index == 1 and bought[1].count == 10,
    "single queue vendor purchase bought the wrong amount")

bought = {}
assert(vendors.BuyQueueAll() == true, "Buy All vendor purchase failed")
assert(#bought == 2 and bought[1].count == 10 and bought[2].count == 2,
    "Buy All did not buy each available queue shortage")

money, bought = 50, {}
assert(vendors.BuyQueueAll() == false and #bought == 0, "vendor purchase ignored the total gold check")
assert(#printed > 0, "not-enough-gold failure was not reported")

print("Vendor queue buying regression test: PASS")
