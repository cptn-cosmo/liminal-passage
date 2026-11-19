-- Liminal Passage: core namespace, saved variables, events, helpers.
local ADDON_NAME, ns = ...
LiminalPassage = ns

ns.PREFIX = "LIMPASS"
ns.CHANNEL = "LiminalPassage"
ns.ITEM_NAME = "Scroll of Liminal Passage"
ns.DEFAULT_ITEM_ID = 213548
ns.DEFAULT_ICON = "Interface\\Icons\\INV_Scroll_05"
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")) or "dev"

ns.STATUS = {
    online = {
        label = "Online", color = "ff33ff66",
        desc = "Others can find you and teleport to you automatically.",
    },
    busy = {
        label = "Busy", color = "ffffcc33",
        desc = "Others can find you, but you approve every teleport request.",
    },
    offline = {
        label = "Offline", color = "ff999999",
        desc = "Invisible: you behave as if the addon was not installed.",
    },
}
ns.STATUS_ORDER = { "online", "busy", "offline" }

local defaults = {
    status = "online",
    leaveAfter = true,
    itemID = nil,
    framePos = nil,
    buttonPos = nil,
}

ns.results = {}        -- [fullName] = result table (traveler side)
ns.hostPending = {}    -- [fullName] = { rid, expires, popup } (host side)

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event]) do
        fn(...)
    end
end)

-- Lightweight change notification for UI / map pins.
local listeners = {}
function ns:Listen(fn) listeners[#listeners + 1] = fn end
function ns:Notify()
    for _, fn in ipairs(listeners) do fn() end
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function ns:Print(...)
    print("|cffb48cffLiminal Passage|r:", ...)
end

function ns.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end

function ns.Token()
    return ("%06x"):format(math.random(0, 0xffffff))
end

function ns.Clean(s)
    return (tostring(s or ""):gsub("[~|\r\n]", ""))
end

local function realm()
    return GetNormalizedRealmName() or (GetRealmName() or ""):gsub("[%s%-]", "")
end

function ns.FullName(name)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. realm()
end

function ns.ShortName(name)
    return name and Ambiguate(name, "short") or "?"
end

-- Name usable for /target, UnitInParty, InviteUnit (realm stripped if same realm).
function ns.UnitName(name)
    return Ambiguate(name, "none")
end

function ns:Me()
    if not self.me then
        local n, r = UnitFullName("player")
        if not n then return nil end
        self.me = n .. "-" .. (r or realm())
    end
    return self.me
end

function ns.ClassColored(name, classFile)
    local c = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    if c then return c:WrapTextInColorCode(name) end
    return name
end

function ns.StatusText(status)
    local s = ns.STATUS[status]
    if not s then return status or "?" end
    return ("|c%s%s|r"):format(s.color, s.label)
end

function ns:IsGroupedWith(name)
    local n = ns.UnitName(name)
    return UnitInParty(n) or UnitInRaid(n) ~= nil
end

---------------------------------------------------------------------------
-- Scroll lookup
---------------------------------------------------------------------------
function ns:FindScroll()
    local id = self.db.itemID or ns.DEFAULT_ITEM_ID
    local count = C_Item.GetItemCount(id)
    if count and count > 0 then return id, count end

    local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, lastBag do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local name = info.itemName or C_Item.GetItemNameByID(info.itemID)
                if name == ns.ITEM_NAME then
                    self.db.itemID = info.itemID
                    return info.itemID, C_Item.GetItemCount(info.itemID)
                end
            end
        end
    end
    return nil, 0
end

---------------------------------------------------------------------------
-- Location
---------------------------------------------------------------------------
function ns:GetLocation()
    local mapID = C_Map.GetBestMapForUnit("player")
    local x, y
    if mapID then
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if pos then x, y = pos:GetXY() end
    end
    return mapID, x, y, GetRealZoneText() or "", GetSubZoneText() or ""
end

function ns:MapAncestry(mapID)
    local list, guard = {}, 0
    while mapID and mapID > 0 and guard < 20 do
        local info = C_Map.GetMapInfo(mapID)
        if not info then break end
        list[#list + 1] = info
        mapID = info.parentMapID
        guard = guard + 1
    end
    return list
end

-- Host side: does my current location satisfy a search?
function ns:MatchesQuery(qMapID, qText)
    local mapID, _, _, zone, sub = self:GetLocation()
    local ancestry = self:MapAncestry(mapID)
    if qMapID and qMapID > 0 then
        for _, info in ipairs(ancestry) do
            if info.mapID == qMapID then return true end
        end
        return false
    end
    qText = (qText or ""):lower()
    if qText == "" then return true end
    local function has(s) return s and s ~= "" and s:lower():find(qText, 1, true) end
    if has(zone) or has(sub) then return true end
    for _, info in ipairs(ancestry) do
        if has(info.name) then return true end
    end
    return false
end

function ns:WorldPos(mapID, x, y)
    if not (mapID and x and y) then return end
    local cont, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
    if cont and pos then return cont, pos end
end

-- Distance in yards between two map positions (nil if on different continents).
function ns:Distance(m1, x1, y1, m2, x2, y2)
    local c1, p1 = self:WorldPos(m1, x1, y1)
    local c2, p2 = self:WorldPos(m2, x2, y2)
    if not c1 or not c2 or c1 ~= c2 then return end
    local ax, ay = p1:GetXY()
    local bx, by = p2:GetXY()
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Project a result onto another map (for world map pins).
function ns:ProjectToMap(r, mapID)
    if r.mapID == mapID then return r.x, r.y end
    local c, p = self:WorldPos(r.mapID, r.x, r.y)
    if not c then return end
    local _, mp = C_Map.GetMapPosFromWorldPos(c, p, mapID)
    if mp then return mp:GetXY() end
end

---------------------------------------------------------------------------
-- Status
---------------------------------------------------------------------------
function ns:SetStatus(status)
    if not ns.STATUS[status] then return end
    self.db.status = status
    if status == "offline" then
        self:LeaveChannel()
        self:ClearHostPending()
    else
        self:JoinChannel()
    end
    self:Print("Status set to " .. ns.StatusText(status) .. ".")
    self:Notify()
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    LiminalPassageDB = LiminalPassageDB or {}
    for k, v in pairs(defaults) do
        if LiminalPassageDB[k] == nil then LiminalPassageDB[k] = v end
    end
    ns.db = LiminalPassageDB
end)

ns:On("PLAYER_LOGIN", function()
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
    -- Give the default channels time to join first so ours doesn't steal /1.
    C_Timer.After(8, function()
        if ns.db.status ~= "offline" then ns:JoinChannel() end
    end)
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_LIMINALPASSAGE1 = "/lp"
SLASH_LIMINALPASSAGE2 = "/liminal"
SlashCmdList.LIMINALPASSAGE = function(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then
        ns:ToggleUI()
    elseif ns.STATUS[cmd] then
        ns:SetStatus(cmd)
    elseif cmd == "search" then
        ns:ShowUI()
        ns:Search({ text = rest })
    elseif cmd == "cancel" then
        ns:CancelTravel()
    elseif cmd == "item" then
        local id = tonumber(rest)
        if id then
            ns.db.itemID = id
            ns:Print("Scroll item ID set to " .. id .. ".")
        else
            ns.db.itemID = nil
            ns:Print("Scroll item ID reset; it will be detected by name.")
        end
        ns:Notify()
    elseif cmd == "resetpos" then
        ns:ResetPositions()
    else
        ns:Print("Commands:")
        print("  /lp - toggle window")
        print("  /lp online | busy | offline - set your status")
        print("  /lp search <zone or subzone> - find hosts there (empty = anywhere)")
        print("  /lp cancel - cancel the current teleport")
        print("  /lp item <itemID> - override the scroll item ID (no ID = auto-detect)")
        print("  /lp resetpos - reset window and button positions")
        print("  World map: 'Liminal' button searches the shown map, Alt+Click searches near a spot.")
    end
end

-- Addon compartment (minimap addon menu)
function LiminalPassage_OnAddonCompartmentClick() ns:ToggleUI() end
function LiminalPassage_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine("Liminal Passage")
    GameTooltip:AddLine("Status: " .. ns.StatusText(ns.db and ns.db.status), 1, 1, 1)
    GameTooltip:AddLine("Click to open.", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end
function LiminalPassage_OnAddonCompartmentLeave() GameTooltip:Hide() end

-- Key binding labels (Bindings.xml)
BINDING_HEADER_LIMINALPASSAGE = "Liminal Passage"
BINDING_NAME_LIMINALPASSAGE_TOGGLE = "Toggle window"
_G["BINDING_NAME_CLICK LiminalPassageUseButton:LeftButton"] = "Use scroll on destination player"
