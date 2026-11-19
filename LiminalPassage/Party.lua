-- Liminal Passage: request handshake, grouping and the secure "use scroll" button.
--
-- Traveler (has the scroll)            Host (resting at the destination)
--   R~rid  ------------------------->  offline: ignore | busy: W~rid + popup | online: accept
--          <-------------------------  A~rid~solo|lead|same   or   D~rid~reason
--   solo: traveler invites host        (host auto-accepts the invite)
--   lead: I~rid ------------------->   host invites traveler (traveler auto-accepts)
--   in group -> secure button armed -> one click: /target host, /use scroll
--   T~rid  ------------------------->  done
local _, ns = ...

local REQUEST_TIMEOUT = 60
local HOST_PENDING_TIME = 120

local REASONS = {
    notresting = "they are not resting in an inn or city",
    grouped = "they are in a group they don't lead",
    full = "their group is full",
    declined = "they declined",
    combat = "they are in combat",
}

---------------------------------------------------------------------------
-- Secure button (standalone so the main window never becomes protected)
---------------------------------------------------------------------------
local btn = CreateFrame("Button", "LiminalPassageUseButton", UIParent, "SecureActionButtonTemplate")
btn:SetSize(52, 52)
btn:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
btn:SetFrameStrata("HIGH")
btn:Hide()
btn:RegisterForClicks("AnyUp", "AnyDown")
btn:SetAttribute("type", "macro")
btn:SetAttribute("shift-type*", "none") -- shift is reserved for dragging

btn.icon = btn:CreateTexture(nil, "ARTWORK")
btn.icon:SetAllPoints()
btn.icon:SetTexture(ns.DEFAULT_ICON)
btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

btn.glow = btn:CreateTexture(nil, "OVERLAY")
btn.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
btn.glow:SetBlendMode("ADD")
btn.glow:SetVertexColor(0.7, 0.5, 1)
btn.glow:SetPoint("CENTER")
btn.glow:SetSize(100, 100)
local pulse = btn.glow:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0.25)
fade:SetDuration(0.7)
btn:HookScript("OnShow", function() pulse:Play() end)
btn:HookScript("OnHide", function() pulse:Stop() end)

btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
btn.label:SetPoint("TOP", btn, "BOTTOM", 0, -6)
btn.hint = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
btn.hint:SetPoint("TOP", btn.label, "BOTTOM", 0, -2)
btn.hint:SetText("Click to teleport - Shift-drag to move")

btn:SetMovable(true)
btn:SetClampedToScreen(true)
btn:RegisterForDrag("LeftButton")
btn:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() and not InCombatLockdown() then self:StartMoving() end
end)
btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    ns.db.buttonPos = { point, rel, x, y }
end)
btn:SetScript("OnEnter", function(self)
    local t = ns.travel
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Liminal Passage")
    if t then
        GameTooltip:AddLine("Targets " .. ns.ShortName(t.target) .. " and uses your scroll on them.", 1, 1, 1, true)
    end
    GameTooltip:AddLine("Both of you must be resting (inn or city).", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
ns.useButton = btn

function ns:ResetPositions()
    if InCombatLockdown() then return self:Print("Can't do that in combat.") end
    self.db.buttonPos, self.db.framePos = nil, nil
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", UIParent, "CENTER", 0, 180)
    if self.ResetFramePosition then self:ResetFramePosition() end
end

local function applySecure()
    if InCombatLockdown() then
        ns.secureDirty = true
        return
    end
    ns.secureDirty = false
    local t = ns.travel
    if t and t.state == "ready" and t.itemID then
        btn:SetAttribute("macrotext", ("/target %s\n/use item:%d"):format(ns.UnitName(t.target), t.itemID))
        btn.icon:SetTexture(C_Item.GetItemIconByID(t.itemID) or ns.DEFAULT_ICON)
        btn.label:SetText("Teleport to " .. ns.ShortName(t.target))
        btn:Show()
    else
        btn:SetAttribute("macrotext", nil)
        btn:Hide()
    end
end

---------------------------------------------------------------------------
-- Traveler side
---------------------------------------------------------------------------
local function isActive(t)
    return t and t.state ~= "failed" and t.state ~= "done" and t.state ~= "cancelled"
end
ns.IsTravelActive = function() return isActive(ns.travel) end

function ns:SetTravelState(state, message)
    local t = self.travel
    if not t then return end
    t.state = state
    t.message = message
    applySecure()
    self:Notify()
end

function ns:TravelFail(message)
    local t = self.travel
    if not t then return end
    self:Print("|cffff5555" .. message .. "|r")
    if isActive(t) then self:Whisper(t.target, "C", t.rid) end
    self:SetTravelState("failed", message)
end

function ns:RequestTeleport(name)
    name = ns.FullName(name)
    if not name then return end
    if InCombatLockdown() then return self:Print("You can't do that in combat.") end

    local itemID = self:FindScroll()
    if not itemID then
        return self:Print("You don't have a " .. ns.ITEM_NAME .. " (mage only). Use /lp item <id> if it was not detected.")
    end
    if not IsResting() then
        self:Print("|cffffcc33Warning:|r you are not resting. The scroll only works from an inn or city.")
    end

    if isActive(self.travel) then self:CancelTravel(true) end

    local t = { target = name, rid = ns.Token(), state = "requested", itemID = itemID, started = GetTime() }
    self.travel = t

    -- Always ask, even if already grouped, so the host's busy/offline status is respected.
    self:Whisper(name, "R", t.rid)
    self:SetTravelState("requested", "Asking " .. ns.ShortName(name) .. "...")

    C_Timer.After(REQUEST_TIMEOUT, function()
        if self.travel == t and isActive(t) and t.state ~= "ready" then
            self:TravelFail(ns.ShortName(name) .. " did not respond.")
        end
    end)
end

function ns:CancelTravel(silent)
    local t = self.travel
    if not t then return end
    if isActive(t) then
        self:Whisper(t.target, "C", t.rid)
        if t.createdGroup and self:IsGroupedWith(t.target) and GetNumGroupMembers() <= 2 then
            C_PartyInfo.LeaveParty()
        end
    end
    if not silent then self:Print("Teleport cancelled.") end
    self:SetTravelState("cancelled", "Cancelled.")
end

function ns:ArmButton()
    local t = self.travel
    if not isActive(t) then return end
    local itemID = self:FindScroll()
    if not itemID then return self:TravelFail("No " .. ns.ITEM_NAME .. " left in your bags.") end
    t.itemID = itemID
    self:SetTravelState("ready", "Ready - click the scroll button to teleport to " .. ns.ShortName(t.target) .. ".")
    PlaySound(SOUNDKIT.READY_CHECK)
    self:Print("Grouped with " .. ns.ShortName(t.target) .. ". Click the glowing scroll button (or your keybind) to teleport.")
end

local function forActive(sender, f)
    local t = ns.travel
    if isActive(t) and t.target == sender and t.rid == f[2] then return t end
end

ns.msg = ns.msg or {}

ns.msg.W = function(self, sender, f)
    if not forActive(sender, f) then return end
    self:SetTravelState("waiting", ns.ShortName(sender) .. " is busy - waiting for them to accept...")
end

ns.msg.D = function(self, sender, f)
    if not forActive(sender, f) then return end
    self:TravelFail(("%s can't receive you: %s."):format(ns.ShortName(sender), REASONS[f[3]] or f[3] or "unknown"))
end

ns.msg.A = function(self, sender, f)
    local t = forActive(sender, f)
    if not t then return end
    local hostState = f[3]

    if hostState == "same" or self:IsGroupedWith(sender) then
        return self:ArmButton()
    end

    if hostState == "solo" then
        if IsInGroup() and not UnitIsGroupLeader("player") then
            return self:TravelFail("You're in a group but not its leader, so you can't invite " .. ns.ShortName(sender) .. ".")
        end
        if IsInGroup() and not IsInRaid() and GetNumGroupMembers() >= 5 then
            return self:TravelFail("Your group is full.")
        end
        t.createdGroup = not IsInGroup()
        self:SetTravelState("inviting", "Inviting " .. ns.ShortName(sender) .. "...")
        C_PartyInfo.InviteUnit(ns.UnitName(sender))
    elseif hostState == "lead" then
        if IsInGroup() then
            return self:TravelFail(ns.ShortName(sender) .. " leads another group. Leave your group first.")
        end
        t.createdGroup = true
        self:SetTravelState("awaitinvite", "Waiting for " .. ns.ShortName(sender) .. "'s group invite...")
        self:Whisper(sender, "I", t.rid)
    else
        self:TravelFail("Unexpected reply from " .. ns.ShortName(sender) .. ".")
    end
end

---------------------------------------------------------------------------
-- Host side
---------------------------------------------------------------------------
local lastRequest = {}

function ns:HostGroupState(traveler)
    if not IsInGroup() then return "solo" end
    if self:IsGroupedWith(traveler) then return "same" end
    if not UnitIsGroupLeader("player") then return nil, "grouped" end
    if not IsInRaid() and GetNumGroupMembers() >= 5 then return nil, "full" end
    return "lead"
end

function ns:HostAccept(sender, rid)
    if self.db.status == "offline" then return end
    local state, err = self:HostGroupState(sender)
    if not state then return self:Whisper(sender, "D", rid, err) end
    if not IsResting() then return self:Whisper(sender, "D", rid, "notresting") end
    local p = self.hostPending[sender] or {}
    p.rid, p.expires = rid, GetTime() + HOST_PENDING_TIME
    self.hostPending[sender] = p
    self:Whisper(sender, "A", rid, state)
    self:Print(ns.ShortName(sender) .. " is on their way - they'll teleport to you shortly.")
end

function ns:ClearHostPending()
    for sender, p in pairs(self.hostPending) do
        if p.popup then StaticPopup_Hide("LIMINAL_PASSAGE_REQUEST", p.popup) end
        self.hostPending[sender] = nil
    end
end

StaticPopupDialogs["LIMINAL_PASSAGE_REQUEST"] = {
    text = "%s wants to teleport to you with a Scroll of Liminal Passage.\n\nYou'll be grouped with them. Allow it?",
    button1 = ACCEPT,
    button2 = DECLINE,
    timeout = 40,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(_, data)
        if data and not data.handled then
            data.handled = true
            ns:HostAccept(data.sender, data.rid)
        end
    end,
    OnCancel = function(_, data)
        if data and not data.handled then
            data.handled = true
            ns:Whisper(data.sender, "D", data.rid, "declined")
            ns.hostPending[data.sender] = nil
        end
    end,
}

ns.msg.R = function(self, sender, f)
    if self.db.status == "offline" then return end -- as if not installed
    local rid = f[2]
    local now = GetTime()
    if lastRequest[sender] and now - lastRequest[sender] < 5 then return end
    lastRequest[sender] = now

    if InCombatLockdown() then return self:Whisper(sender, "D", rid, "combat") end
    if not IsResting() then return self:Whisper(sender, "D", rid, "notresting") end
    local _, err = self:HostGroupState(sender)
    if err then return self:Whisper(sender, "D", rid, err) end

    if self.db.status == "busy" then
        self:Whisper(sender, "W", rid)
        local data = { sender = sender, rid = rid }
        self.hostPending[sender] = { rid = rid, expires = 0, popup = data } -- not accepted yet
        PlaySound(SOUNDKIT.READY_CHECK)
        if FlashClientIcon then FlashClientIcon() end
        StaticPopup_Show("LIMINAL_PASSAGE_REQUEST", ns.ShortName(sender), nil, data)
    else
        self:HostAccept(sender, rid)
    end
end

-- Traveler (who joined our group as leader) asks us to invite them.
ns.msg.I = function(self, sender, f)
    local p = self.hostPending[sender]
    if not p or p.rid ~= f[2] or p.expires < GetTime() then return end
    C_PartyInfo.InviteUnit(ns.UnitName(sender))
end

ns.msg.C = function(self, sender, f)
    local p = self.hostPending[sender]
    if not p or p.rid ~= f[2] then return end
    if p.popup then
        p.popup.handled = true
        StaticPopup_Hide("LIMINAL_PASSAGE_REQUEST", p.popup)
    end
    self.hostPending[sender] = nil
    self:Print(ns.ShortName(sender) .. " cancelled their teleport.")
end

ns.msg.T = function(self, sender, f)
    local p = self.hostPending[sender]
    if not p or p.rid ~= f[2] then return end
    self.hostPending[sender] = nil
    self:Print(ns.ShortName(sender) .. " used their scroll and is arriving.")
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
ns:On("PLAYER_LOGIN", function()
    local pos = ns.db.buttonPos
    if pos then
        btn:ClearAllPoints()
        btn:SetPoint(pos[1], UIParent, pos[2] or pos[1], pos[3], pos[4])
    end
end)

ns:On("PARTY_INVITE_REQUEST", function(inviter)
    if ns.IsSecret(inviter) then return end
    local who = ns.FullName(inviter)
    local ok = false
    local t = ns.travel
    if isActive(t) and t.target == who and t.state == "awaitinvite" then ok = true end
    local p = ns.hostPending[who]
    if p and p.expires > GetTime() and ns.db.status ~= "offline" then ok = true end
    if not ok then return end

    AcceptGroup()
    -- The invite popup may be shown after this event fires.
    StaticPopup_Hide("PARTY_INVITE")
    C_Timer.After(0, function() StaticPopup_Hide("PARTY_INVITE") end)
end)

ns:On("GROUP_ROSTER_UPDATE", function()
    local t = ns.travel
    if not isActive(t) then return end
    local grouped = ns:IsGroupedWith(t.target)
    if grouped and (t.state == "inviting" or t.state == "awaitinvite") then
        ns:ArmButton()
    elseif not grouped and t.state == "ready" then
        ns:TravelFail(ns.ShortName(t.target) .. " left the group.")
    end
end)

ns:On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or ns.IsSecret(spellID) then return end
    local t = ns.travel
    if not (t and t.state == "ready" and t.itemID) then return end
    local _, scrollSpell = C_Item.GetItemSpell(t.itemID)
    if not scrollSpell or scrollSpell ~= spellID then return end

    ns:Whisper(t.target, "T", t.rid)
    ns:SetTravelState("done", "Teleported to " .. ns.ShortName(t.target) .. ".")
    if ns.db.leaveAfter and t.createdGroup then
        C_Timer.After(5, function()
            if IsInGroup() and GetNumGroupMembers() <= 2 then C_PartyInfo.LeaveParty() end
        end)
    end
end)

ns:On("PLAYER_REGEN_ENABLED", function()
    if ns.secureDirty then applySecure() end
end)
