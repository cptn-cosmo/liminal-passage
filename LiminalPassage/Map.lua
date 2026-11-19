-- Liminal Passage: world map integration (search button, Alt+Click, result pins).
local _, ns = ...

local PIN_TEMPLATE = "LiminalPassagePinTemplate"

---------------------------------------------------------------------------
-- Pin mixin (must exist before MapPin.xml loads)
---------------------------------------------------------------------------
LiminalPassagePinMixin = CreateFromMixins(MapCanvasPinMixin)

function LiminalPassagePinMixin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    self:SetScalingLimits(1, 1.0, 1.2)
end

function LiminalPassagePinMixin:OnAcquired(result, x, y)
    self.result = result
    self:SetPosition(x, y)
    if result.status == "busy" then
        self.Border:SetColorTexture(1, 0.8, 0.2, 1)
    else
        self.Border:SetColorTexture(0.2, 1, 0.4, 1)
    end
end

function LiminalPassagePinMixin:OnMouseEnter()
    local r = self.result
    if not r then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.ClassColored(ns.ShortName(r.name), r.class))
    GameTooltip:AddLine(("Level %s - %s"):format(r.level or "?", ns.StatusText(r.status)), 1, 1, 1)
    local where = (r.sub ~= "" and r.sub ~= r.zone) and (r.sub .. ", " .. r.zone) or r.zone
    GameTooltip:AddLine(where, 0.8, 0.8, 0.8)
    if r.dist then GameTooltip:AddLine(("%d yards from your search spot"):format(r.dist), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(r.status == "busy" and "Click to ask for a teleport." or "Click to teleport here.", 0.7, 0.5, 1)
    GameTooltip:Show()
end

function LiminalPassagePinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

function LiminalPassagePinMixin:OnMouseUp(button)
    if button == "LeftButton" and self.result then
        ns:RequestTeleport(self.result.name)
        ns:ShowUI()
    end
end

---------------------------------------------------------------------------
-- Data provider
---------------------------------------------------------------------------
local Provider = CreateFromMixins(MapCanvasDataProviderMixin)

function Provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function Provider:RefreshAllData()
    self:RemoveAllData()
    local map = self:GetMap()
    local shownMap = map:GetMapID()
    if not shownMap then return end
    for _, r in pairs(ns.results) do
        local x, y = ns:ProjectToMap(r, shownMap)
        if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            map:AcquirePin(PIN_TEMPLATE, r, x, y)
        end
    end
end

---------------------------------------------------------------------------
-- Setup once the world map exists
---------------------------------------------------------------------------
local function setup()
    if ns.mapReady or not WorldMapFrame then return end
    ns.mapReady = true

    WorldMapFrame:AddDataProvider(Provider)
    ns:Listen(function()
        if WorldMapFrame:IsShown() then Provider:RefreshAllData() end
    end)

    local container = WorldMapFrame.ScrollContainer

    local b = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    b:SetSize(150, 24)
    b:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 8, 8)
    b:SetFrameLevel(container:GetFrameLevel() + 50)
    b:SetText("Liminal: search here")
    b:SetScript("OnClick", function()
        local mapID = WorldMapFrame:GetMapID()
        if mapID then
            ns:ShowUI()
            ns:Search({ mapID = mapID })
        end
    end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Liminal Passage")
        GameTooltip:AddLine("Find addon users resting anywhere on the shown map.", 1, 1, 1, true)
        GameTooltip:AddLine("Alt+Click a spot on the map to sort by distance from it.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ns.mapButton = b

    -- Alt+Click: capture on mouse down, before the map navigates to a child zone.
    local pendingPoint
    container:HookScript("OnMouseDown", function(self, button)
        pendingPoint = nil
        if button ~= "LeftButton" or not IsAltKeyDown() then return end
        local mapID = WorldMapFrame:GetMapID()
        local x, y = self:GetNormalizedCursorPosition()
        if mapID and x and y then pendingPoint = { mapID = mapID, x = x, y = y } end
    end)
    container:HookScript("OnMouseUp", function(_, button)
        local point = pendingPoint
        pendingPoint = nil
        if not point or button ~= "LeftButton" then return end
        local info = C_Map.GetMapInfo(point.mapID)
        ns:ShowUI()
        -- Search the clicked map (and its children), sorted by distance to the spot.
        ns:Search({ mapID = point.mapID, point = point,
            label = "near a spot in " .. (info and info.name or "the map") })
        if WorldMapFrame:GetMapID() ~= point.mapID then
            WorldMapFrame:SetMapID(point.mapID) -- undo any zoom-in the click caused
        end
    end)
end

if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
    setup()
else
    ns:On("ADDON_LOADED", function(name)
        if name == "Blizzard_WorldMap" then setup() end
    end)
end
ns:On("PLAYER_LOGIN", setup)
