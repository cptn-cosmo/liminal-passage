-- Liminal Passage: main window.
local _, ns = ...

local ROW_HEIGHT = 40

local UI = CreateFrame("Frame", "LiminalPassageFrame", UIParent, "BasicFrameTemplateWithInset")
UI:SetSize(500, 470)
UI:SetPoint("CENTER")
UI:SetFrameStrata("DIALOG")
UI:SetClampedToScreen(true)
UI:SetMovable(true)
UI:EnableMouse(true)
UI:RegisterForDrag("LeftButton")
UI:SetScript("OnDragStart", UI.StartMoving)
UI:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.framePos = { point, rel, x, y }
end)
UI:Hide()
tinsert(UISpecialFrames, UI:GetName())

UI.title = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
UI.title:SetPoint("TOP", 0, -5)
UI.title:SetText("Liminal Passage")

function ns:ResetFramePosition()
    UI:ClearAllPoints()
    UI:SetPoint("CENTER")
end

---------------------------------------------------------------------------
-- Status row
---------------------------------------------------------------------------
local statusLabel = UI:CreateFontString(nil, "OVERLAY", "GameFontNormal")
statusLabel:SetPoint("TOPLEFT", 16, -36)
statusLabel:SetText("Your status:")

UI.statusButtons = {}
local prev
for _, key in ipairs(ns.STATUS_ORDER) do
    local b = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
    b:SetSize(84, 22)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", statusLabel, "RIGHT", 10, 0) end
    b:SetText(ns.STATUS[key].label)
    b:SetScript("OnClick", function() ns:SetStatus(key) end)
    UI.statusButtons[key] = b
    prev = b
end

UI.statusDesc = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
UI.statusDesc:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -10)
UI.statusDesc:SetPoint("RIGHT", -16, 0)
UI.statusDesc:SetJustifyH("LEFT")

---------------------------------------------------------------------------
-- Search row
---------------------------------------------------------------------------
local search = CreateFrame("EditBox", nil, UI, "InputBoxTemplate")
search:SetSize(200, 22)
search:SetPoint("TOPLEFT", 24, -92)
search:SetAutoFocus(false)
search:SetMaxLetters(60)
search.placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
search.placeholder:SetPoint("LEFT", 2, 0)
search.placeholder:SetText("Zone, city or inn subzone...")
search:SetScript("OnTextChanged", function(self)
    self.placeholder:SetShown(self:GetText() == "")
end)
search:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    ns:Search({ text = self:GetText() })
end)
search:SetScript("OnEscapePressed", search.ClearFocus)
UI.searchBox = search

local function button(text, width, anchor, onClick)
    local b = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local searchBtn = button("Search", 70, search, function()
    search:ClearFocus()
    ns:Search({ text = search:GetText() })
end)
local anyBtn = button("Anywhere", 80, searchBtn, function()
    search:SetText("")
    ns:Search({})
end)
button("World Map", 84, anyBtn, function()
    if ToggleWorldMap then ToggleWorldMap() end
end)

local hint = UI:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", 18, -120)
hint:SetText("World map: click the Liminal button to search the shown map, or Alt+Click a spot.")

UI.header = UI:CreateFontString(nil, "OVERLAY", "GameFontNormal")
UI.header:SetPoint("TOPLEFT", 18, -140)
UI.header:SetPoint("RIGHT", -18, 0)
UI.header:SetJustifyH("LEFT")

---------------------------------------------------------------------------
-- Results list
---------------------------------------------------------------------------
local scroll = CreateFrame("ScrollFrame", nil, UI, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -158)
scroll:SetPoint("BOTTOMRIGHT", -34, 84)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(1, 1)
scroll:SetScrollChild(content)
scroll:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)

UI.empty = scroll:CreateFontString(nil, "OVERLAY", "GameFontDisable")
UI.empty:SetPoint("TOP", 0, -30)
UI.empty:SetWidth(380)

local rows = {}
local function getRow(i)
    if rows[i] then return rows[i] end
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(ROW_HEIGHT)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
    r:SetPoint("RIGHT", content, "RIGHT")

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.08)

    r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.btn:SetSize(80, 22)
    r.btn:SetPoint("RIGHT", -6, 0)
    r.btn:SetScript("OnClick", function(self)
        local res = self:GetParent().result
        if res then ns:RequestTeleport(res.name) end
    end)

    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", 8, -5)
    r.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.status:SetPoint("LEFT", r.name, "RIGHT", 8, 0)
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.info:SetPoint("BOTTOMLEFT", 8, 6)
    r.info:SetPoint("RIGHT", r.btn, "LEFT", -6, 0)
    r.info:SetJustifyH("LEFT")
    r.info:SetWordWrap(false)

    rows[i] = r
    return r
end

---------------------------------------------------------------------------
-- Bottom: travel status, options
---------------------------------------------------------------------------
UI.travel = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
UI.travel:SetPoint("BOTTOMLEFT", 18, 56)
UI.travel:SetPoint("RIGHT", -110, 0)
UI.travel:SetJustifyH("LEFT")
UI.travel:SetWordWrap(true)

UI.cancel = CreateFrame("Button", nil, UI, "UIPanelButtonTemplate")
UI.cancel:SetSize(90, 22)
UI.cancel:SetPoint("BOTTOMRIGHT", -14, 52)
UI.cancel:SetText(CANCEL)
UI.cancel:SetScript("OnClick", function() ns:CancelTravel() end)

local leave = CreateFrame("CheckButton", nil, UI, "UICheckButtonTemplate")
leave:SetSize(24, 24)
leave:SetPoint("BOTTOMLEFT", 12, 16)
leave.label = leave:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
leave.label:SetPoint("LEFT", leave, "RIGHT", 2, 0)
leave.label:SetText("Leave the group after teleporting")
leave:SetScript("OnClick", function(self) ns.db.leaveAfter = self:GetChecked() end)
UI.leaveCheck = leave

UI.scrolls = UI:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
UI.scrolls:SetPoint("BOTTOMRIGHT", -18, 22)

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local function locationText(r)
    local where = r.zone
    if r.sub ~= "" and r.sub ~= r.zone then where = r.sub .. ", " .. r.zone end
    local parts = { ("Lvl %s"):format(r.level or "?"), where }
    if r.dist then parts[#parts + 1] = ("%d yd"):format(r.dist) end
    return table.concat(parts, "  -  ")
end

function UI:Refresh()
    if not self:IsShown() or not ns.db then return end
    local status = ns.db.status
    for key, b in pairs(self.statusButtons) do
        if key == status then b:LockHighlight() else b:UnlockHighlight() end
        b:SetText(key == status and ns.StatusText(key) or ns.STATUS[key].label)
    end
    self.statusDesc:SetText(ns.STATUS[status].desc)
    self.leaveCheck:SetChecked(ns.db.leaveAfter)

    local s = ns.search
    local list = ns:SortedResults()
    if s then
        self.header:SetText(("Resting players %s: %d%s"):format(s.label, #list, s.done and "" or "  (searching...)"))
    else
        self.header:SetText("Search for a destination to find resting players.")
    end

    local busyTravel = ns.IsTravelActive()
    for i, res in ipairs(list) do
        local row = getRow(i)
        row.result = res
        row.name:SetText(ns.ClassColored(ns.ShortName(res.name), res.class))
        row.status:SetText(ns.StatusText(res.status))
        row.info:SetText(locationText(res))
        row.btn:SetText(res.status == "busy" and "Ask" or "Teleport")
        local isTarget = ns.travel and ns.travel.target == res.name and busyTravel
        row.btn:SetEnabled(not isTarget)
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(1, #list * ROW_HEIGHT))

    if s and s.done and #list == 0 then
        self.empty:SetText("Nobody with Liminal Passage is resting there right now.")
    elseif not s then
        self.empty:SetText("Type a zone, city or inn subzone (e.g. Goldshire), or use the world map.")
    else
        self.empty:SetText("")
    end

    local t = ns.travel
    self.travel:SetText(t and t.message or "")
    self.cancel:SetShown(busyTravel)

    local itemID, count = ns:FindScroll()
    if itemID then
        self.scrolls:SetText(("Scrolls: |cffffffff%d|r"):format(count or 0))
    else
        self.scrolls:SetText("|cffff5555No scroll in bags|r")
    end
end

UI:SetScript("OnShow", function(self) self:Refresh() end)
ns:Listen(function() UI:Refresh() end)
ns:On("BAG_UPDATE_DELAYED", function() UI:Refresh() end)
ns:On("PLAYER_LOGIN", function()
    local pos = ns.db.framePos
    if pos then
        UI:ClearAllPoints()
        UI:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3], pos[4])
    end
end)

function ns:ShowUI() UI:Show() end
function ns:ToggleUI() UI:SetShown(not UI:IsShown()) end
ns.frame = UI
