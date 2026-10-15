-- Run with Lua 5.1 from the repository root: the Crafting Queue vendor backend rounds
-- shortages to merchant bundles, respects limited stock, buys only from a click, and
-- copies its plan before merchant updates can change the live list.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local settings, applyHooks = {}, {}
local merchantShown = false
local purchases, messages = {}, {}
local merchantItems = {
    { item = 111, price = 200, stack = 5, available = -1 },
    { item = 222, price = 100, stack = 5, available = 1 },
}
local materials = {
    { item = 111, qty = 7 },
    { item = 222, qty = 7 },
    { item = 333, qty = 4 },
}

local function Noop() end
local frameMethods = {}
function frameMethods.RegisterEvent() end
function frameMethods.UnregisterAllEvents() end
function frameMethods.SetScript(f, name, fn) f.scripts[name] = fn end
local frameMeta = { __index = function(_, key) return frameMethods[key] or Noop end }

local ns = {
    L = dofile("Tools/regression/locale_stub.lua").L,
    Upper = string.upper,
    Lower = string.lower,
    UI = {
        ModuleSettings = function(_, defaults)
            local store, listeners = {}, {}
            function store.Get(key)
                if settings[key] == nil then return defaults[key] end
                return settings[key]
            end
            function store.Set(key, value)
                settings[key] = value
                for index = 1, #listeners do listeners[index](key, value) end
            end
            function store.OnChange(fn) listeners[#listeners + 1] = fn end
            return store
        end,
    },
    ProfWindowAPI = {},
    AccountSettings = function() return settings.account end,
    Print = function(message) messages[#messages + 1] = message end,
}
settings.account = {}

local env = setmetatable({
    NaowhForever = ns,
    CreateFrame = function() return setmetatable({ scripts = {} }, frameMeta) end,
    hooksecurefunc = function(target, name, fn)
        if target == ns and name == "Apply" then applyHooks[#applyHooks + 1] = fn end
    end,
    wipe = function(list) for key in pairs(list) do list[key] = nil end end,
    C_MerchantFrame = {
        GetItemInfo = function(index)
            local item = merchantItems[index]
            return item and { price = item.price, stackCount = item.stack,
                numAvailable = item.available, hasExtendedCost = false }
        end,
    },
    C_Item = {
        GetItemInfo = function()
            return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 7
        end,
    },
    Enum = { ItemClass = { Tradegoods = 7 } },
    MerchantFrame = { IsShown = function() return merchantShown end },
    GetMerchantNumItems = function() return #merchantItems end,
    GetMerchantItemID = function(index) return merchantItems[index] and merchantItems[index].item end,
    GetMerchantItemMaxStack = function(index) return merchantItems[index].stack end,
    GetMoney = function() return 10000 end,
    BuyMerchantItem = function(index, count)
        purchases[#purchases + 1] = { index = index, count = count }
    end,
}, { __index = _G })
env._G = env

Load({ "Core/Features.lua", "NaowhForever_Professions/Professions.lua" }, env)
local P = ns.Professions
P.Recipes = {
    Link = function(itemID) return "item:" .. itemID end,
    Owned = function() return {} end,
    Reagents = function() return {} end,
}
P.Text = { Money = tostring }
P.CraftQueue = {
    VendorMaterials = function() return materials end,
    AddMissingToShopping = function() return true end,
}
Load({ "NaowhForever_Professions/Vendors.lua" }, env)

local list, total = P.Vendors.QueueList()
check("only materials sold by this merchant are listed", #list == 2)
check("unlimited stock rounds seven items to two five-item bundles",
    list[1].itemID == 111 and list[1].want == 7 and list[1].count == 10 and list[1].cost == 400)
check("limited stock marks the unmet remainder",
    list[2].itemID == 222 and list[2].count == 5 and list[2].short == true)
check("the total uses whole merchant purchases", total == 500)
check("listing materials never buys anything", #purchases == 0)

check("buying one shortage succeeds", P.Vendors.BuyQueueItem(111) == true)
check("a click buys the rounded item count in merchant-sized chunks",
    #purchases == 2 and purchases[1].count == 5 and purchases[2].count == 5)
check("the purchase reports what was bought", #messages == 1)

print(("test-profession-vendor-queue: %d checks passed"):format(checks))
