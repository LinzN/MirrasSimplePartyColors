-- Mirra's Simple Party Colors
-- Colors the health bars of the original party frames (PartyFrame) in class colors.
-- Raid-style party frames (CompactPartyFrame) are intentionally NOT touched.

local ADDON = ...
local PREFIX = "|cff33ccffMSPC|r: "

---------------------------------------------------------------------------
-- Strings
---------------------------------------------------------------------------
local L = {
    SUBTITLE      = "Class colors for the original party frames.",
    ENABLED       = "Class-colored health bars",
    ENABLED_DESC  = "Colors your party members' health bars in their class color.",
    NAME          = "Class-colored names",
    NAME_DESC     = "Also colors the name above each party frame.",
    FLAT          = "Flat bar texture",
    FLAT_DESC     = "Uses a plain texture instead of the desaturated Blizzard texture (stronger colors).",
    PREVIEW       = "Preview",
    PREVIEW_DESC  = "(dummy party – updates live with your settings)",
    SHUFFLE       = "Shuffle classes",
    RESET         = "Restore defaults",
    RESET_DONE    = "Settings restored to defaults.",
    HINT          = "Note: Only affects the original party frames. \"Use Raid-Style Party Frames\" must be disabled in the Blizzard options.\nQuick access: /mspc",
    ON            = "on",
    OFF           = "off",
    CHAT_ENABLED  = "Class colors",
    CHAT_NAME     = "Class-colored names",
    CHAT_FLAT     = "Flat texture",
}



local defaults = {
    enabled   = true,  -- class-colored health bars
    colorName = false, -- class-colored names too
    flat      = false, -- flat texture instead of desaturated Blizzard texture
}

local FLAT_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"

local db
local hooked = {}
local originalNameColor = {}

---------------------------------------------------------------------------
-- Find frames (modern PartyFrame + fallback for old PartyMemberFrameN)
---------------------------------------------------------------------------
local function GetMemberFrames()
    local frames = {}
    if PartyFrame then
        if PartyFrame.PartyMemberFramePool and PartyFrame.PartyMemberFramePool.EnumerateActive then
            for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                frames[#frames + 1] = frame
            end
        end
        if #frames == 0 then
            for i = 1, 4 do
                local f = PartyFrame["MemberFrame" .. i]
                if f then frames[#frames + 1] = f end
            end
        end
    end
    if #frames == 0 then
        for i = 1, 4 do
            local f = _G["PartyMemberFrame" .. i]
            if f then frames[#frames + 1] = f end
        end
    end
    return frames
end

local function GetHealthBar(frame)
    return frame.healthbar
        or frame.HealthBar
        or (frame.HealthBarContainer and frame.HealthBarContainer.HealthBar)
        or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "HealthBar"])
end

local function GetNameText(frame)
    return frame.name or frame.Name
        or (frame.GetName and frame:GetName() and _G[frame:GetName() .. "Name"])
end

local function GetUnit(frame)
    return frame.unit or (frame.GetAttribute and frame:GetAttribute("unit"))
end

---------------------------------------------------------------------------
-- Apply colors
---------------------------------------------------------------------------
local function GetClassColor(unit)
    if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return end
    local _, class = UnitClass(unit)
    if not class then return end
    local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
end

-- IMPORTANT (Midnight/Forever "secret values"):
-- This addon never calls Blizzard frame functions and never writes fields
-- into Blizzard tables. Otherwise Blizzard's own code becomes "tainted" and
-- fails on secret values (e.g. the health bar's maxValue).
-- Only widget methods (color/texture) are used; state lives in our own tables.

local barState = setmetatable({}, { __mode = "k" })

local function GetState(bar)
    local st = barState[bar]
    if not st then
        st = {}
        barState[bar] = st
    end
    return st
end

local function RememberOriginalTexture(bar, st)
    local tex = bar:GetStatusBarTexture()
    if not tex then return end
    st.origAtlas = tex.GetAtlas and tex:GetAtlas() or nil
    st.origTexture = (not st.origAtlas) and tex:GetTexture() or nil
end

local function RestoreBar(bar, st)
    if st.flat then
        if st.origAtlas then
            local tex = bar:GetStatusBarTexture()
            if tex and tex.SetAtlas then tex:SetAtlas(st.origAtlas, true) end
        elseif st.origTexture then
            bar:SetStatusBarTexture(st.origTexture)
        end
        st.flat = nil
    end
    local tex = bar:GetStatusBarTexture()
    if tex and tex.SetDesaturated then tex:SetDesaturated(false) end
    bar:SetStatusBarColor(1, 1, 1)
    st.colored = nil
end

local function ApplyToFrame(frame)
    if not frame or not db then return end
    local bar = GetHealthBar(frame)
    local unit = GetUnit(frame)
    local r, g, b = GetClassColor(unit)
    local active = db.enabled and r ~= nil

    if bar then
        local st = GetState(bar)
        local offline = db.enabled and unit and UnitExists(unit) and UnitIsConnected and not UnitIsConnected(unit)
        if offline then
            -- Offline: show gray like Blizzard does
            local tex = bar:GetStatusBarTexture()
            if tex and tex.SetDesaturated then tex:SetDesaturated(true) end
            bar:SetStatusBarColor(0.5, 0.5, 0.5)
            st.colored = true
        elseif active then
            if db.flat then
                if not st.flat then
                    RememberOriginalTexture(bar, st)
                    bar:SetStatusBarTexture(FLAT_TEXTURE)
                    st.flat = true
                end
            elseif st.flat then
                RestoreBar(bar, st)
            end
            local tex = bar:GetStatusBarTexture()
            if tex and tex.SetDesaturated then tex:SetDesaturated(true) end
            bar:SetStatusBarColor(r, g, b)
            st.colored = true
        elseif st.colored or st.flat then
            RestoreBar(bar, st)
        end
    end

    local name = GetNameText(frame)
    if name then
        if not originalNameColor[name] then
            originalNameColor[name] = { name:GetTextColor() }
        end
        if db.colorName and active then
            name:SetTextColor(r, g, b)
        else
            local o = originalNameColor[name]
            name:SetTextColor(o[1], o[2], o[3])
        end
    end
end

local function HookFrame(frame)
    if hooked[frame] then return end
    hooked[frame] = true

    -- Blizzard resets the bar art in these methods -> recolor afterwards
    local function onArtReset()
        local bar = GetHealthBar(frame)
        if bar and barState[bar] then barState[bar].flat = nil end -- Blizzard set its own texture
        ApplyToFrame(frame)
    end
    for _, method in ipairs({ "ToPlayerArt", "ToVehicleArt" }) do
        if type(frame[method]) == "function" then
            hooksecurefunc(frame, method, onArtReset)
        end
    end
    for _, method in ipairs({ "UpdateMember", "UpdateArt", "Setup" }) do
        if type(frame[method]) == "function" then
            hooksecurefunc(frame, method, function() ApplyToFrame(frame) end)
        end
    end

    frame:HookScript("OnShow", function() ApplyToFrame(frame) end)
end

local function UpdateAll()
    for _, frame in ipairs(GetMemberFrames()) do
        HookFrame(frame)
        ApplyToFrame(frame)
    end
end

local CreateOptionsPanel -- defined below

---------------------------------------------------------------------------
-- Events & global hooks
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("UNIT_NAME_UPDATE")
f:RegisterEvent("UNIT_ENTERED_VEHICLE")
f:RegisterEvent("UNIT_EXITED_VEHICLE")
f:RegisterEvent("UNIT_CONNECTION")

f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        MSPC_DB = MSPC_DB or {}
        for k, v in pairs(defaults) do
            if MSPC_DB[k] == nil then MSPC_DB[k] = v end
        end
        db = MSPC_DB

        if PartyFrame and type(PartyFrame.UpdatePartyFrames) == "function" then
            hooksecurefunc(PartyFrame, "UpdatePartyFrames", UpdateAll)
        end
        if type(UnitFrameHealthBar_Update) == "function" then
            hooksecurefunc("UnitFrameHealthBar_Update", function(bar)
                if not bar then return end
                local parent = bar.unitFrame or bar.partyFrame
                if not parent and bar.GetParent then
                    parent = bar:GetParent()
                    if parent and not hooked[parent] and parent.GetParent then parent = parent:GetParent() end
                end
                if parent and hooked[parent] then ApplyToFrame(parent) end
            end)
        end
        CreateOptionsPanel()
        self:UnregisterEvent("ADDON_LOADED")
        return
    end
    if not db then return end
    -- defer one frame so Blizzard updates first
    C_Timer.After(0, UpdateAll)
end)


---------------------------------------------------------------------------
-- Settings panel (Options -> AddOns -> Mirra's Simple Party Colors)
---------------------------------------------------------------------------
local PANEL_NAME = "Mirra's Simple Party Colors"
local settingsCategory
local panel
local checkboxes = {}

local function OpenSettings()
    if Settings and Settings.OpenToCategory and settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

local function CreateCheckbox(parent, key, label, desc, anchor, yOffset)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor == parent.title and -2 or 0, yOffset)

    local text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(label)

    local sub = cb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
    sub:SetWidth(520)
    sub:SetJustifyH("LEFT")
    sub:SetText(desc)

    cb:SetScript("OnClick", function(self)
        db[key] = self:GetChecked() and true or false
        if PlaySound and SOUNDKIT then
            PlaySound(db[key] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        UpdateAll()
        parent:Refresh()
    end)

    cb.key = key
    cb.label = text
    cb.desc = sub
    checkboxes[#checkboxes + 1] = cb
    return cb
end

CreateOptionsPanel = function()
    panel = CreateFrame("Frame")
    panel.name = PANEL_NAME

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(PANEL_NAME)
    panel.title = title

    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetText(L.SUBTITLE)

    local anchorForFirst = CreateFrame("Frame", nil, panel)
    anchorForFirst:SetSize(1, 1)
    anchorForFirst:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -2, -10)

    local cbEnabled = CreateCheckbox(panel, "enabled",
        L.ENABLED, L.ENABLED_DESC,
        anchorForFirst, -4)

    local cbName = CreateCheckbox(panel, "colorName",
        L.NAME, L.NAME_DESC,
        cbEnabled, -22)

    local cbFlat = CreateCheckbox(panel, "flat",
        L.FLAT, L.FLAT_DESC,
        cbName, -22)
    cbName.dependsOnEnabled = true
    cbFlat.dependsOnEnabled = true

    -- Live preview: dummy party members drawn with our own widgets
    local previewTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    previewTitle:SetPoint("TOPLEFT", cbFlat, "BOTTOMLEFT", 2, -34)
    previewTitle:SetText(L.PREVIEW)

    local previewSub = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    previewSub:SetPoint("LEFT", previewTitle, "RIGHT", 8, 0)
    previewSub:SetText(L.PREVIEW_DESC)

    local dummyNames = { "Thandrel", "Lyssia", "Brukk", "Venna" }
    local dummyFill  = { 0.92, 0.64, 0.81, 0.47 }
    local dummyHP    = { "41.2k", "22.8k", "33.5k", "17.1k" }
    local dummyClass = { "PALADIN", "MAGE", "DRUID", "HUNTER" }
    local dummies = {}

    local function SetClassIcon(tex, class)
        if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
            tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
        else
            tex:SetTexCoord(0, 1, 0, 1)
            tex:SetAtlas("classicon-" .. class:lower())
        end
    end

    for i = 1, 4 do
        local d = CreateFrame("Frame", nil, panel)
        d:SetSize(260, 44)
        d:SetPoint("TOPLEFT", previewTitle, "BOTTOMLEFT", 0, -10 - (i - 1) * 50)

        local ring = d:CreateTexture(nil, "BACKGROUND")
        ring:SetSize(44, 44)
        ring:SetPoint("LEFT", 0, 0)
        ring:SetColorTexture(0, 0, 0, 0)
        local portrait = d:CreateTexture(nil, "ARTWORK")
        portrait:SetSize(40, 40)
        portrait:SetPoint("CENTER", ring, "CENTER")

        local name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        name:SetPoint("TOPLEFT", ring, "TOPRIGHT", 6, -2)
        name:SetText(dummyNames[i])

        local hp = CreateFrame("StatusBar", nil, d)
        hp:SetSize(190, 14)
        hp:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
        hp:SetMinMaxValues(0, 1)
        hp:SetValue(dummyFill[i])
        local hpBg = hp:CreateTexture(nil, "BACKGROUND")
        hpBg:SetAllPoints()
        hpBg:SetColorTexture(0, 0, 0, 0.7)
        local hpText = hp:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
        hpText:SetPoint("CENTER")
        hpText:SetText(dummyHP[i])

        local mp = CreateFrame("StatusBar", nil, d)
        mp:SetSize(190, 6)
        mp:SetPoint("TOPLEFT", hp, "BOTTOMLEFT", 0, -2)
        mp:SetStatusBarTexture(FLAT_TEXTURE)
        mp:SetStatusBarColor(0, 0.45, 1)
        mp:SetMinMaxValues(0, 1)
        mp:SetValue(0.85)
        local mpBg = mp:CreateTexture(nil, "BACKGROUND")
        mpBg:SetAllPoints()
        mpBg:SetColorTexture(0, 0, 0, 0.7)

        d.portrait, d.name, d.hp = portrait, name, hp
        dummies[i] = d
    end

    local shuffleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    shuffleBtn:SetSize(140, 22)
    shuffleBtn:SetPoint("LEFT", dummies[1], "RIGHT", 16, 0)
    shuffleBtn:SetText(L.SHUFFLE)
    shuffleBtn:SetScript("OnClick", function()
        local pool = {}
        for _, class in ipairs(CLASS_SORT_ORDER or dummyClass) do
            if RAID_CLASS_COLORS[class] then pool[#pool + 1] = class end
        end
        for i = 1, 4 do
            if #pool == 0 then break end
            dummyClass[i] = table.remove(pool, math.random(#pool))
        end
        panel:Refresh()
    end)

    -- Blizzard's own party health texture (read-only lookup, cached)
    local blizzBarAtlas
    local function GetBlizzardBarAtlas()
        if blizzBarAtlas then return blizzBarAtlas end
        for _, frame in ipairs(GetMemberFrames()) do
            local bar = GetHealthBar(frame)
            if bar then
                local st = barState[bar]
                local atlas = st and st.origAtlas
                if not atlas and not (st and st.flat) then
                    local tex = bar:GetStatusBarTexture()
                    atlas = tex and tex.GetAtlas and tex:GetAtlas()
                end
                if atlas then blizzBarAtlas = atlas; return atlas end
            end
        end
        local guess = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health"
        if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(guess) then
            blizzBarAtlas = guess
        end
        return blizzBarAtlas
    end

    local function RefreshDummies()
        local atlas = GetBlizzardBarAtlas()
        for i, d in ipairs(dummies) do
            local class = dummyClass[i]
            local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or RAID_CLASS_COLORS[class]
            SetClassIcon(d.portrait, class)

            local hp = d.hp
            if db.enabled and db.flat then
                hp:SetStatusBarTexture(FLAT_TEXTURE)
            elseif atlas then
                hp:SetStatusBarTexture(FLAT_TEXTURE) -- ensure a texture object exists
                hp:GetStatusBarTexture():SetAtlas(atlas)
            else
                hp:SetStatusBarTexture("Interface\\RaidFrame\\Raid-Bar-Hp-Fill")
            end
            local tex = hp:GetStatusBarTexture()

            if db.enabled and c then
                if tex and tex.SetDesaturated then tex:SetDesaturated(true) end
                hp:SetStatusBarColor(c.r, c.g, c.b)
            else
                if tex and tex.SetDesaturated then tex:SetDesaturated(false) end
                if atlas and not db.flat then
                    hp:SetStatusBarColor(1, 1, 1) -- Blizzard atlas is already green
                else
                    hp:SetStatusBarColor(0, 1, 0)
                end
            end

            if db.enabled and db.colorName and c then
                d.name:SetTextColor(c.r, c.g, c.b)
            else
                d.name:SetTextColor(1, 0.82, 0)
            end
        end
    end

    -- Buttons
    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(180, 24)
    resetBtn:SetPoint("TOPLEFT", dummies[4], "BOTTOMLEFT", 0, -20)
    resetBtn:SetText(L.RESET)
    resetBtn:SetScript("OnClick", function()
        for k, v in pairs(defaults) do db[k] = v end
        UpdateAll()
        panel:Refresh()
        print(PREFIX .. L.RESET_DONE)
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 2, -10)
    hint:SetWidth(520)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.HINT)

    function panel:Refresh()
        for _, cb in ipairs(checkboxes) do
            cb:SetChecked(db[cb.key])
            local enabled = not cb.dependsOnEnabled or db.enabled
            if enabled then
                cb:Enable()
                cb.label:SetFontObject("GameFontHighlight")
            else
                cb:Disable()
                cb.label:SetFontObject("GameFontDisable")
            end
        end
        RefreshDummies()
    end
    panel:SetScript("OnShow", panel.Refresh)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, PANEL_NAME)
        Settings.RegisterAddOnCategory(settingsCategory)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

---------------------------------------------------------------------------
-- Slash commands: /mspc opens the settings
---------------------------------------------------------------------------
local function OnOff(v) return v and ("|cff00ff00" .. L.ON .. "|r") or ("|cffff0000" .. L.OFF .. "|r") end

SLASH_MSPC1 = "/mspc"
SLASH_MSPC2 = "/mspartycolors"
SlashCmdList.MSPC = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "toggle" then
        db.enabled = not db.enabled
        print(PREFIX .. L.CHAT_ENABLED .. " " .. OnOff(db.enabled))
    elseif msg == "name" then
        db.colorName = not db.colorName
        print(PREFIX .. L.CHAT_NAME .. " " .. OnOff(db.colorName))
    elseif msg == "flat" then
        db.flat = not db.flat
        print(PREFIX .. L.CHAT_FLAT .. " " .. OnOff(db.flat))
    else
        OpenSettings()
        return
    end
    UpdateAll()
    if panel and panel:IsShown() then panel:Refresh() end
end
