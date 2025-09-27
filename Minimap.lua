-- AIOS Mini Map Icon
-- Author: Poorkingz/Aios
-- Guild: Cult of Elune
-- Description: A sleek, nature-infused minimap button, snapping to the minimap's edge with druidic grace.
-- Sprout actions: Left-Click toggles the main interface, Right-Click blooms the wellbeing panel, Shift+Right-Click opens settings, Ctrl+Left-Click dances around the minimap.

-- Configuration constants: Sow the seeds of our icon's design
local ICON_SIZE = 30.9 -- 3% larger than 30x30, a sturdy sapling
local ICON_TEXTURE_SIZE = 20.6 -- 3% larger than 20x20, a vibrant leaf
local BORDER_SIZE = 51.5 -- 3% larger than 50x50, a protective bark
local BORDER_OFFSET_X = 9.27 -- Adjusted for 3% larger size (9*1.03)
local BORDER_OFFSET_Y = -10.3 -- Adjusted for 3% larger size (-10*1.03)
local SNAP_RADIUS = 95 -- Snap to the minimap's edge, rooted firmly
local PINK_COLOR = "|cFFFF77FF" -- Radiant pink for the interface
local WHITE_COLOR = "|cFFFFFFFF" -- Moonlight white for clarity

local PINK_RGB = {1, 0.467, 1} -- #FF77FF for tooltip border

-- LibDataBroker + LibDBIcon integration (preferred path)
local ldb = LibStub and LibStub("LibDataBroker-1.1", true)
local ldi = LibStub and LibStub("LibDBIcon-1.0", true)

if ldb and ldi then
    -- Create a launcher-type data object for the minimap
    local dataObj = ldb:NewDataObject("GlitterHealth", {
        type  = "launcher",
        icon  = "Interface\\Icons\\inv_valentinescandy",
        label = "GlitterHealth",
        OnClick = function(_, button)
            if button == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
                if ui and ui.frame then
                    if ui.frame:IsShown() then ui.frame:Hide() else ui.frame:Show() end
                end
            elseif button == "RightButton" and IsShiftKeyDown() and not IsControlKeyDown() then
                if SettingsUtil and SettingsUtil.Open then SettingsUtil:Open() end
            elseif button == "RightButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
                if NS and NS.ToggleWellbeing then NS.ToggleWellbeing() end
            end
        end,
        OnTooltipShow = function(tooltip)
            if not tooltip or not tooltip.AddLine then return end
            tooltip:ClearLines()
            tooltip:AddLine("|cFFFF77FFGlitterHealth|r")
            tooltip:AddLine("|cFFFFFFFFLeft-Click: |r|cFFFF77FFToggle GlitterHealth overlay|r")
            tooltip:AddLine("|cFFFFFFFFRight-Click: |r|cFFFF77FFToggle Wellbeing window|r")
            tooltip:AddLine("|cFFFFFFFFShift+Right-Click: |r|cFFFF77FFOpen Settings|r")
        end,
    })

    -- Ensure saved variables structure exists and register with LibDBIcon
    GlitterHealthDB = GlitterHealthDB or {}
    GlitterHealthDB.minimap = GlitterHealthDB.minimap or { hide = false }
    ldi:Register("GlitterHealth", dataObj, GlitterHealthDB.minimap)

    -- Stop here so the manual Minimap button code below is not executed when LDB/DBIcon are available
    return
end

-- Initialize the minimap button: Plant the seed for our UI
local button = CreateFrame("Button", "GlitterHealth_MinimapIcon", Minimap)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:SetSize(ICON_SIZE, ICON_SIZE)
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:EnableMouse(true)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp") -- Listen for both claws
button:RegisterForDrag("LeftButton") -- Drag with Ctrl+Left-Click, like a bear's stride
button:SetMovable(true)

-- Icon texture: A heart of nature to guide the grove
local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\inv_valentinescandy")
icon:SetSize(ICON_TEXTURE_SIZE, ICON_TEXTURE_SIZE)
icon:SetPoint("CENTER")
button.icon = icon

-- Border texture: Bark to shield our icon, non-interactive
local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("CENTER", BORDER_OFFSET_X, BORDER_OFFSET_Y)
border:SetSize(BORDER_SIZE, BORDER_SIZE)
border:SetMouseClickEnabled(false)

-- Positioning: Root the button around the minimap's edge
local angle = GlitterHealthDB and GlitterHealthDB.minimapAngle or 0
local function UpdatePosition()
    button:ClearAllPoints()
    local x = SNAP_RADIUS * math.cos(angle)
    local y = SNAP_RADIUS * math.sin(angle)
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Save position: Anchor the roots in saved variables
local function SavePosition()
    if GlitterHealthDB then
        GlitterHealthDB.minimapAngle = angle
        GlitterHealthDB.minimapRadius = SNAP_RADIUS
    end
end

-- Drag handling: Prowl smoothly around the minimap with Ctrl+Left-Click
button:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" and IsControlKeyDown() then
        self:LockHighlight() -- Glow like a moonlit grove
        self.isDragging = true
        self:SetScript("OnUpdate", function(self)
            if self.isDragging and IsControlKeyDown() then
                local centerX, centerY = Minimap:GetCenter()
                local mouseX, mouseY = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                mouseX = mouseX / scale
                mouseY = mouseY / scale
                local dx = mouseX - centerX
                local dy = mouseY - centerY
                angle = math.atan2(dy, dx)
                UpdatePosition() -- Flow like a river around the minimap
            elseif self.isDragging then
                self:LockHighlight(false) -- Rest in the shade
                self.isDragging = false
                self:SetScript("OnUpdate", nil)
                SavePosition() -- Plant the new position
            end
        end)
    end
end)

button:SetScript("OnMouseUp", function(self, btn)
    if self.isDragging and btn == "LeftButton" then
        self:LockHighlight(false) -- Return to the forest's calm
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
        SavePosition() -- Root the position firmly
    end
end)

-- Click handling: Branch out with druidic actions
button:SetScript("OnClick", function(self, button, down)
    if button == "LeftButton" and IsControlKeyDown() then return end -- Let the bear prowl
    if button == "LeftButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
        -- Left-Click: Toggle the main interface, like shifting forms
        if ui and ui.frame then
            if ui.frame:IsShown() then
                ui.frame:Hide()
            else
                ui.frame:Show()
            end
        end
    elseif button == "RightButton" and IsShiftKeyDown() and not IsControlKeyDown() then
        -- Shift+Right-Click: Open settings, sprouting options
        if SettingsUtil and SettingsUtil.Open then
            SettingsUtil:Open()
        end
    elseif button == "RightButton" and not IsShiftKeyDown() and not IsControlKeyDown() then
        -- Right-Click: Toggle wellbeing panel, blooming serenity
        if NS and NS.ToggleWellbeing then
            NS.ToggleWellbeing()
        end
    end
end)

-- Tooltip: Display a moonlit guide with a radiant sparkle
button:SetScript("OnEnter", function(self)
    GameTooltip:Hide()
    GameTooltip:SetOwner(self, "ANCHOR_TOP") -- Hover above like a wisp
    GameTooltip:ClearLines()
    GameTooltip.NineSlice:SetBorderColor(unpack(PINK_RGB)) -- Pink border, a druid's vibrant aura
    GameTooltip:AddDoubleLine(PINK_COLOR.."GlitterHealth", "", unpack(PINK_RGB)) -- Centered pink title
    GameTooltip:AddLine(WHITE_COLOR.."Left-Click: "..PINK_COLOR.."Toggle GlitterHealth overlay")
    GameTooltip:AddLine(WHITE_COLOR.."Right-Click: "..PINK_COLOR.."Toggle Wellbeing window")
    GameTooltip:AddLine(WHITE_COLOR.."Shift+Right-Click: "..PINK_COLOR.."Open Settings")
    GameTooltip:Show()
end)

button:SetScript("OnLeave", function(self)
    GameTooltip.NineSlice:SetBorderColor(1, 1, 1, 1) -- Restore moonlight white border
    GameTooltip:Hide()
end)

-- Initialize: Sprout the button in its rightful place
UpdatePosition()
