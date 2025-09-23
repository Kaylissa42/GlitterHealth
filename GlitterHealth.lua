-- GlitterHealth - v1.1.1
-- Author: Kaylissa

local ADDON_NAME, NS = ...
NS = NS or {}

-- ===== version info =====
NS.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GlitterHealth","Version")) or "0.0.0"

local function __gh_versionTuple(v)
  local a,b,c = string.match(v or "", "^(%d+)%.?(%d*)%.?(%d*)$")
  return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end
local function __gh_isNewer(vOther, vMine)
  local A1,A2,A3 = __gh_versionTuple(vOther)
  local B1,B2,B3 = __gh_versionTuple(vMine)
  if A1 ~= B1 then return A1 > B1 end
  if A2 ~= B2 then return A2 > B2 end
  return A3 > B3
end
-- ========================


local DB
local DB_VERSION = 39

-- ========= utils =========
local function todayKey() return date("%Y-%m-%d") end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function round(n,p) local m=10^(p or 0) return math.floor(n*m+0.5)/m end
local function yd_to_mi(yd) return (yd or 0)/1760 end
local function safeint(n) n = tonumber(n) or 0; if n<0 then n=0 end; return math.floor(n+0.5) end
local function seedFrom(str) local s=0 for i=1,#str do s=(s*31 + string.byte(str,i))%2147483647 end return s end
local function pickFrom(list, seed) if #list==0 then return nil end return list[(seed % #list) + 1] end
local SECTION_HEX = "FF4DFF"
local VIBE_HEX    = "B84DFF"
local DAILY_STATS_HEX    = "FF00FF" -- Magenta
local DAILY_VIBES_HEX    = "FF66CC" -- Pink
local HEADER_HEX = "FF66CC" -- Pink for all headers
local function colorize(hex, txt) return "|cFF"..hex..tostring(txt).."|r" end

-- LibSharedMedia
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- Returns a file path for the chosen statusbar texture, with a safe fallback
local function GH_GetBarTexturePath()
  local name = (DB and DB.profile and DB.profile.barTexture) or "Blizzard"
  if LSM then
    local tex = LSM:Fetch("statusbar", name, true)
    if tex then return tex end
  end
  -- Blizzard fallback
  return "Interface\\TARGETINGFRAME\\UI-StatusBar"
end

local retextureBars -- forward declaration for texture refresher

-- ===== goal emote helpers =====
local function GH_GetPronoun()
  local s = UnitSex("player")
  if s == 3 then return "her"   -- female
  elseif s == 2 then return "his" -- male
  else return "their" end
end

local function GH_FormatGoalLabel(label)
  -- Map your internal labels to nice emote text
  if label == "Walk"      then return "Walking"
  elseif label == "Swim"  then return "Swimming"
  elseif label == "Move"  then return "Move (Calories)"
  elseif label == "Steps" then return "Steps"
  elseif label == "Exercise" then return "Exercise"
  elseif label == "Jumps" then return "Jumps"
  else return tostring(label or "Goal") end
end

local function GH_DoGoalEmotes(label)
  local pron = GH_GetPronoun()
  local pretty = GH_FormatGoalLabel(label)
  -- /em <msg>
  local msg = string.format("just completed %s %s Goal!", pron, pretty)
  -- Send as an EMOTE so it shows like: "<YourName> just completed her Walking Goal!"
  -- (EMOTE is equivalent to /e and /me)
  SendChatMessage(msg, "EMOTE")
  -- Then /cheer
  if DoEmote then DoEmote("CHEER") end
end

-- ===== pretty /gh help (star bullets that render in WoW chat) =====
local GH_COLOR = "FF77FF"  -- addon pink
local GH_DIM   = "B0B0B0"
local function GH_c(hex, s) return "|cFF"..hex..tostring(s).."|r" end
local function GH_tag(s)    return GH_c(GH_COLOR, s) end
local function GH_dim(s)    return GH_c(GH_DIM, s) end

-- Cute star icon (12x12). You can swap the path to any icon you love.
-- A few fun options:
--   "Interface\\Buttons\\UI-GroupLoot-Dice-Up"
--   "Interface\\COMMON\\star"
--   "Interface\\Buttons\\UI-GuildButton-PublicNote-Up"
local GH_STAR = "|TInterface\\ICONS\\ability_monk_forcesphere_pink:14:14|t"

function NS.PrintGHHelp()
  local v = NS.VERSION or "?"
  print(GH_tag("GlitterHealth ")..GH_dim("— v"..v.."  (type ")..GH_tag("/gh help")..GH_dim(" anytime)"))

  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh options")..GH_dim(" — Open Settings"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh mood").." | "..GH_tag("/gh well").." | "..GH_tag("/gh wellbeing")..GH_dim(" — Wellbeing window"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh export").." | "..GH_tag("/gh csv")..GH_dim(" — CSV Export window"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh hide").." | "..GH_tag("/gh show")..GH_dim(" — Hide/Show the bars"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh lock").." | "..GH_tag("/gh unlock")..GH_dim(" — Lock/Unlock the frame"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh reset")..GH_dim(" — Reset TODAY’s stats"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh center")..GH_dim(" — Center the window on screen"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh debugjumps")..GH_dim(" — Toggle jump debug text"))
  print(GH_dim(" "..GH_STAR.." ")..GH_tag("/gh ver")..GH_dim(" — Show version & ping group/guild for newer versions"))
end

-- Mark already-complete goals as "notified" for TODAY (without playing anything).
local function GH_PreMarkTodayGoals()
  if not DB or not DB.data then return end
  local d = DB.data[DB.today]; if not d then return end
  local g = DB.profile and DB.profile.goals; if not g then return end

  d.goalsNotified = d.goalsNotified or {}

  local miW = (d.distanceFootYd or 0) / 1760
  local miS = (d.distanceSwimYd or 0) / 1760

  local calGoal = math.max(g.calories    or 0, GH_GOAL_MIN.calories)
  local stpGoal = math.max(g.steps       or 0, GH_GOAL_MIN.steps)
  local exmGoal = math.max(g.exerciseMin or 0, GH_GOAL_MIN.exerciseMin)
  local wlkGoal = math.max(g.milesWalk   or 0, GH_GOAL_MIN.milesWalk)
  local swmGoal = math.max(g.milesSwim   or 0, GH_GOAL_MIN.milesSwim)
  local jmpGoal = math.max(g.jumps       or 0, GH_GOAL_MIN.jumps)

  if (d.calories or 0)         >= calGoal then d.goalsNotified.move  = true end
  if (d.steps or 0)            >= stpGoal then d.goalsNotified.steps = true end
  if ((d.exerciseSec or 0)/60) >= exmGoal then d.goalsNotified.exer  = true end
  if miW                        >= wlkGoal then d.goalsNotified.walk  = true end
  if miS                        >= swmGoal then d.goalsNotified.swim  = true end
  if (d.jumps or 0)            >= jmpGoal then d.goalsNotified.jump  = true end
end

-- ===== goal minimums & migration =====
local GH_GOAL_MIN = {
  calories    = 1,     -- Kcal
  steps       = 1,
  exerciseMin = 1,     -- minutes
  milesWalk   = 0.1,
  milesSwim   = 0.1,
  jumps       = 1,
}

local function GH_ClampGoals()
  if not (DB and DB.profile and DB.profile.goals) then return end
  local g = DB.profile.goals
  g.calories    = math.max(tonumber(g.calories    or 500) , GH_GOAL_MIN.calories)
  g.steps       = math.max(tonumber(g.steps       or 20000), GH_GOAL_MIN.steps)
  g.exerciseMin = math.max(tonumber(g.exerciseMin or 45)   , GH_GOAL_MIN.exerciseMin)
  g.milesWalk   = math.max(tonumber(g.milesWalk   or 5.0)  , GH_GOAL_MIN.milesWalk)
  g.milesSwim   = math.max(tonumber(g.milesSwim   or 1.0)  , GH_GOAL_MIN.milesSwim)
  g.jumps       = math.max(tonumber(g.jumps       or 1000) , GH_GOAL_MIN.jumps)
end

-- ========= race/sex defaults =========
local DEFAULTS = {
  strideYd = {
    GNOME=2.25, DWARF=2.40, MECHAGNOME=2.25, HUMAN=2.80, UNDEAD=2.70,
    NIGHTELF=3.00, VOIDELF=2.90, DRAENEI=3.00, LIGHTFORGEDDRAENEI=3.00,
    WORGEN=3.00, PANDAREN=2.90, PANDARENALLIANCE=2.90, PANDARENHORDE=2.90,
    DRACTHYR=3.10, VULPERA=2.40, GOBLIN=2.50, ORC=3.00, TAUREN=3.30,
    HIGHMOUNTAINTAUREN=3.30, BLOODELF=2.90, NIGHTBORNE=2.90, TROLL=3.00,
    ZANDALARITROLL=3.10, MAGHARORC=3.00, EARTHENDWARF=2.40, KULTIRAN=3.10,
  },
  weightKg = {
    male   = { GNOME=55, DWARF=80, MECHAGNOME=55, HUMAN=88, NIGHTELF=90, VOIDELF=85, DRAENEI=100, LIGHTFORGEDDRAENEI=100, WORGEN=95, UNDEAD=80, PANDAREN=110, DRACTHYR=95, VULPERA=55, GOBLIN=60, ORC=100, TAUREN=120, HIGHMOUNTAINTAUREN=120, BLOODELF=85, NIGHTBORNE=85, TROLL=95, ZANDALARITROLL=105, MAGHARORC=100, EARTHENDWARF=80, KULTIRAN=105 },
    female = { GNOME=50, DWARF=72, MECHAGNOME=50, HUMAN=75, NIGHTELF=78, VOIDELF=72, DRAENEI=88, LIGHTFORGEDDRAENEI=88, WORGEN=82, UNDEAD=70, PANDAREN=98, DRACTHYR=85, VULPERA=50, GOBLIN=52, ORC=90, TAUREN=105, HIGHMOUNTAINTAUREN=105, BLOODELF=70, NIGHTBORNE=70, TROLL=82, ZANDALARITROLL=90, MAGHARORC=90, EARTHENDWARF=72, KULTIRAN=92 },
  }
}
local function getRaceSex()
  local _, raceFile = UnitRace("player")
  local sex = (UnitSex("player") == 3) and "female" or "male"
  return (raceFile or "HUMAN"):upper(), sex
end
local function getRaceSexDefaults()
  local race, sex = getRaceSex()
  local stride = DEFAULTS.strideYd[race] or 2.8
  local wt = (DEFAULTS.weightKg[sex] and DEFAULTS.weightKg[sex][race]) or 80
  return stride, wt, race, sex
end

-- ========= themes =========
local THEMES = {
  Classic = { move={1.00,0.40,0.60}, steps={0.35,0.95,1.00}, exer={0.50,1.00,0.50}, walk={0.80,0.80,1.00}, swim={0.40,0.70,1.00}, jump={1.00,0.85,0.40}, },
  Pastel  = { move={1.00,0.60,0.75}, steps={0.60,1.00,1.00}, exer={0.65,1.00,0.70}, walk={0.75,0.70,1.00}, swim={0.65,0.85,1.00}, jump={1.00,0.90,0.60}, },
  Neon    = { move={1.00,0.10,0.40}, steps={0.10,1.00,1.00}, exer={0.10,1.00,0.10}, walk={0.40,0.40,1.00}, swim={0.10,0.60,1.00}, jump={1.00,0.80,0.10}, },
  Dark    = { move={0.95,0.25,0.45}, steps={0.20,0.80,0.85}, exer={0.30,0.85,0.40}, walk={0.55,0.55,0.85}, swim={0.25,0.55,0.85}, jump={0.85,0.70,0.25}, },
  Skyline = { move={0.80,0.30,0.65}, steps={0.25,0.70,0.85}, exer={0.30,0.80,0.55}, walk={0.35,0.55,0.85}, swim={0.18,0.40,0.80}, jump={0.70,0.60,0.25}, },
  Spectrum= { move={0.85,0.20,0.20}, steps={0.85,0.55,0.10}, exer={0.80,0.80,0.15}, walk={0.15,0.80,0.20}, swim={0.15,0.45,0.85}, jump={0.55,0.25,0.80}, },
  Sunset  = { move={0.85,0.35,0.20}, steps={0.85,0.60,0.28}, exer={0.80,0.52,0.28}, walk={0.80,0.45,0.35}, swim={0.65,0.42,0.85}, jump={0.85,0.68,0.45}, },
  Ocean   = { move={0.12,0.55,0.75}, steps={0.15,0.70,0.80}, exer={0.20,0.70,0.50}, walk={0.12,0.45,0.80}, swim={0.08,0.32,0.72}, jump={0.20,0.65,0.85}, },
  Forest  = { move={0.45,0.25,0.18}, steps={0.28,0.60,0.35}, exer={0.25,0.70,0.28}, walk={0.15,0.55,0.28}, swim={0.20,0.42,0.50}, jump={0.55,0.48,0.25}, },
  Candy   = { move={0.85,0.40,0.68}, steps={0.70,0.85,0.80}, exer={0.58,0.85,0.68}, walk={0.75,0.68,0.85}, swim={0.62,0.70,0.85}, jump={0.85,0.70,0.58}, }, -- default
  RainbowSparkle = { move={0.85,0.18,0.18}, steps={0.85,0.55,0.00}, exer={0.85,0.75,0.10}, walk={0.00,0.50,0.18}, swim={0.18,0.35,0.70}, jump={0.50,0.18,0.60}, },
  CottonCandy    = { move={0.50,0.65,0.95}, steps={0.90,0.50,0.70}, exer={0.78,0.80,0.85}, walk={0.55,0.75,0.95}, swim={0.90,0.60,0.75}, jump={0.75,0.85,0.95}, },
  Starburst      = { move={0.70,0.62,0.12}, steps={0.80,0.80,0.80}, exer={0.12,0.12,0.12}, walk={0.55,0.25,0.62}, swim={0.32,0.32,0.32}, jump={0.70,0.60,0.15}, },
  TwilightDream  = { move={0.75,0.18,0.48}, steps={0.42,0.18,0.52}, exer={0.18,0.32,0.72}, walk={0.60,0.28,0.52}, swim={0.28,0.36,0.72}, jump={0.75,0.28,0.55}, },
  BubblePop      = { move={0.80,0.70,0.08}, steps={0.80,0.32,0.60}, exer={0.24,0.48,0.80}, walk={0.80,0.45,0.65}, swim={0.28,0.45,0.80}, jump={0.80,0.72,0.20}, },
  MintyFresh     = { move={0.00,0.55,0.28}, steps={0.32,0.70,0.45}, exer={0.75,0.75,0.75}, walk={0.16,0.16,0.16}, swim={0.48,0.78,0.58}, jump={0.28,0.64,0.40}, },
  Starlight      = { move={0.55,0.16,0.65}, steps={0.75,0.75,0.75}, exer={0.16,0.16,0.16}, walk={0.48,0.48,0.48}, swim={0.32,0.32,0.32}, jump={0.64,0.40,0.72}, },
}
local function ensureColorsTable()
  DB.profile.colors = DB.profile.colors or {}
  local t = THEMES[DB.profile.theme] or THEMES.Candy
  for k,v in pairs(t) do if type(v)=="table" and #v==3 then DB.profile.colors[k] = {v[1],v[2],v[3]} end end
end

local ui = {}

local function applyTheme(name)
  if not DB or not DB.profile then return end
  DB.profile.theme = name or DB.profile.theme or "Candy"
  ensureColorsTable()
  local t = THEMES[DB.profile.theme] or THEMES.Candy
  local C = DB.profile.colors
  for k, rgb in pairs(t) do C[k] = {rgb[1],rgb[2],rgb[3]} end
end

-- ========= saved vars =========
local function copyInto(dst, src) for k,v in pairs(src) do if type(v)=="table" then dst[k]=dst[k] or {}; copyInto(dst[k], v) elseif dst[k]==nil then dst[k]=v end end end
local function ensureDayShape(d)
  d.steps = d.steps or 0
  d.calories = d.calories or 0
  d.exerciseSec = d.exerciseSec or 0
  d.distanceFootYd = d.distanceFootYd or 0
  d.distanceSwimYd = d.distanceSwimYd or 0
  d.jumps = d.jumps or 0

  -- NEW: per-day vibes bucket
  d.emotes = d.emotes or {}
  local E = d.emotes
  E.hugs   = E.hugs   or 0
  E.cheers = E.cheers or 0
  E.lols   = E.lols   or 0
  E.waves  = E.waves  or 0
  E.kisses = E.kisses or 0
  E.dances = E.dances or 0
  E.pats   = E.pats   or 0
  E.claps  = E.claps  or 0
  E.boops  = E.boops  or 0
end
local function getDay(db, key) db.data[key] = db.data[key] or {}; ensureDayShape(db.data[key]); return db.data[key] end

local defaults = {
  version = DB_VERSION,
  profile = {
    theme = "Candy",
    colors = {},
    weightKg = 80, stepLengthYd = 2.8,
    goals = { calories = 500, steps = 20000, exerciseMin = 45, milesWalk = 5, milesSwim = 1, jumps = 1000 },
    frame = { x = nil, y = nil, locked = false, scale = 1.0 },
    barWidth = 200,
    barHeight = 18,
    barGap = 0,
    opacity = 1.0,
    barTexture = "Blizzard",
    show = { move=true, steps=true, exer=true, walk=true, swim=true, jump=true },
    hidden = false,
    buttonsPos = "Bottom",
    enableGoalSound = true,
    enableCelebration = true,
    _appliedRace = nil, _appliedSex = nil,
  },
  today = "",
  data = {},
  runtime = {
    inCombat=false, carryStepDist=0, airborne=false, tipIndex=0, goalNotified={},
    jumpFallStartTime=nil, jumpStartZ=nil,
    zHist = {}, -- Z history buffer for ascent-gated jumps
  },
  stats = { hugs=0, cheers=0, lols=0, waves=0, kisses=0, dances=0, pats=0, claps=0, boops=0 },
}

-- ========= frame clamp & center =========
local BAR_HEIGHT = 18

local function clampToScreen(frame)
  if not frame or not frame:GetLeft() then return DB.profile.frame.x, DB.profile.frame.y end
  local scale = frame:GetEffectiveScale()
  local fw, fh = frame:GetWidth()*scale, frame:GetHeight()*scale
  local l, r = UIParent:GetLeft() or 0, UIParent:GetRight() or GetScreenWidth()
  local b, t = UIParent:GetBottom() or 0, UIParent:GetTop() or GetScreenHeight()
  local x = frame:GetLeft()*scale
  local y = frame:GetBottom()*scale
  local pad = 0
  if x < l+pad then x = l+pad end
  if x+fw > r-pad then x = r - pad - fw end
  if y < b+pad then y = b+pad end
  if y+fh > t-pad then y = t - pad - fh end
  local nx, ny = x/scale, y/scale
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", nx, ny)
  return nx, ny
end

local function centerFrame(frame)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:Show()
  local cx, cy = frame:GetCenter()
  local w, h = frame:GetWidth(), frame:GetHeight()
  if not (cx and cy and w and h) then DB.profile.frame.x, DB.profile.frame.y = 0, 0; return end
  local left   = cx - (w / 2)
  local bottom = cy - (h / 2)
  frame:ClearAllPoints()
  frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left, bottom)
  local nx, ny = clampToScreen(frame)
  DB.profile.frame.x, DB.profile.frame.y = nx, ny
end

-- ========= bars & icon buttons =========
local function mkBar(parent, w, h, color)
  local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  holder:SetSize(w, h)
  holder:SetBackdrop({
    bgFile="Interface\\Buttons\\WHITE8X8",
    edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=10,
    insets={left=2,right=2,top=2,bottom=2}
  })
  holder:SetBackdropColor(0,0,0,0.5)
  holder:SetBackdropBorderColor(1,1,1,0.25)

  local bar = CreateFrame("StatusBar", nil, holder)
  bar:SetStatusBarTexture(GH_GetBarTexturePath())
  bar:SetStatusBarColor(unpack(color))
  bar:SetMinMaxValues(0,1); bar:SetValue(0)
  bar:SetPoint("TOPLEFT", holder, "TOPLEFT", 2, -2)
  bar:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -2, 2)
  bar:SetFrameLevel((holder:GetFrameLevel() or 0) + 1)

  local textFrame = CreateFrame("Frame", nil, holder)
  textFrame:SetAllPoints(holder)
  textFrame:SetFrameLevel(bar:GetFrameLevel() + 10)
  local text = textFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetPoint("CENTER")
  local f = text:GetFont(); text:SetFont(f, 10, "OUTLINE")
  text:SetDrawLayer("OVERLAY", 7)

  holder.bar, holder.text = bar, text
  return holder
end

-- icon helpers
local function firstWorkingIcon(candidates)
  for _,c in ipairs(candidates or {}) do if c then return c end end
  return 134400
end
local function getHeartOfAzerothIcon()
  if GetItemIcon then
    local ico = GetItemIcon(158075)
    if ico then return ico end
  end
  return 134400
end
local function mkIconButton(parent, iconCandidates, tooltip, onClick)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(24, 24)
  btn:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1}
  })
  btn:SetBackdropColor(0,0,0,0.35)
  btn:SetBackdropBorderColor(1,1,1,0.10)
  local tex = btn:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 2, -2)
  tex:SetPoint("BOTTOMRIGHT", -2, 2)
  tex:SetTexture(firstWorkingIcon(iconCandidates))
  btn.icon = tex
  btn:SetScript("OnClick", onClick)
  btn:SetMotionScriptsWhileDisabled(true)
  if tooltip and GameTooltip then
    btn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(tooltip)
      GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  return btn
end

local function visibleBarsOrder()
  local sh = DB.profile.show
  local order = {}
  if sh.move then table.insert(order, ui.moveBar) end
  if sh.steps then table.insert(order, ui.stepBar) end
  if sh.exer then table.insert(order, ui.exerBar) end
  if sh.walk then table.insert(order, ui.walkBar) end
  if sh.swim then table.insert(order, ui.swimBar) end
  if sh.jump then table.insert(order, ui.jumpBar) end
  return order
end

local function barsAreaHeight(countBars)
  local gap = clamp(DB.profile.barGap or 0, -6, 8)
  local h = (countBars>0) and (countBars*(DB.profile.barHeight or 18) + (countBars-1)*gap) or 0
  if h < 0 then h = 0 end
  return h
end

local function updateFrameHeight()
  if not ui.frame or not ui.barsContainer or not ui.btnsContainer then return end
  local barsH = barsAreaHeight(#visibleBarsOrder())
  ui.barsContainer:SetHeight(barsH)
  local buttonsH = ui.btnsContainer:GetHeight() or 24
  local total = 10 + barsH + 6 + buttonsH + 8
  ui.frame:SetHeight(math.max(total, 60))
end

local function relayoutBars()
  if not ui.frame or not ui.barsContainer then return end
  local gap = clamp(DB.profile.barGap or 0, -6, 8)
  local order = visibleBarsOrder()
  for i,bar in ipairs(order) do
    bar:ClearAllPoints()
    if i==1 then
      bar:SetPoint("TOP", ui.barsContainer, "TOP", 0, 0) -- always stack downward
    else
      bar:SetPoint("TOP", order[i-1], "BOTTOM", 0, -gap)
    end
    bar:Show()
  end
  for _,b in ipairs({ui.moveBar, ui.stepBar, ui.exerBar, ui.walkBar, ui.swimBar, ui.jumpBar}) do
    local visible=false
    for _,v in ipairs(order) do if v==b then visible=true break end end
    b:SetShown(visible and (not DB.profile.hidden))
  end
  updateFrameHeight()
end

local function positionButtons()
  if not ui.frame or not ui.btnsContainer or not ui.barsContainer then return end
  ui.btnsContainer:ClearAllPoints()
  ui.barsContainer:ClearAllPoints()

  local fullW = (DB.profile.barWidth or 200) + 20
  ui.frame:SetWidth(fullW)

  if (DB.profile.buttonsPos or "Bottom") == "Top" then
    ui.btnsContainer:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 10, -8)
    ui.btnsContainer:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -10, -8)
    ui.btnsContainer:SetHeight(28)
    ui.barsContainer:SetPoint("TOPLEFT", ui.btnsContainer, "BOTTOMLEFT", 0, -6)
    ui.barsContainer:SetPoint("TOPRIGHT", ui.btnsContainer, "BOTTOMRIGHT", 0, -6)
  else
    ui.barsContainer:SetPoint("TOPLEFT", ui.frame, "TOPLEFT", 10, -10)
    ui.barsContainer:SetPoint("TOPRIGHT", ui.frame, "TOPRIGHT", -10, -10)
    ui.btnsContainer:SetPoint("BOTTOMLEFT", ui.frame, "BOTTOMLEFT", 10, 8)
    ui.btnsContainer:SetPoint("BOTTOMRIGHT", ui.frame, "BOTTOMRIGHT", -10, 8)
    ui.btnsContainer:SetHeight(28)
  end

  -- Re-anchor Wellbeing Stats button relative to bars so it follows Top/Bottom setting
  if ui.wellStatsBtn and ui.barsContainer then
    ui.wellStatsBtn:ClearAllPoints()
    if (DB.profile.buttonsPos or "Bottom") == "Top" then
      ui.wellStatsBtn:SetPoint("BOTTOM", ui.barsContainer, "TOP", 0, 2)  -- above bars
    else
      ui.wellStatsBtn:SetPoint("TOP", ui.barsContainer, "BOTTOM", 0, -2) -- below bars
    end
  end

  relayoutBars()
  updateFrameHeight()
end

local function setHidden(hide)
  DB.profile.hidden = not not hide
  if DB.profile.hidden then
    for _,b in ipairs({ui.moveBar, ui.stepBar, ui.exerBar, ui.walkBar, ui.swimBar, ui.jumpBar}) do if b then b:Hide() end end
  else
    if ui.moveBar then ui.moveBar:SetShown(DB.profile.show.move) end
    if ui.stepBar then ui.stepBar:SetShown(DB.profile.show.steps) end
    if ui.exerBar then ui.exerBar:SetShown(DB.profile.show.exer) end
    if ui.walkBar then ui.walkBar:SetShown(DB.profile.show.walk) end
    if ui.swimBar then ui.swimBar:SetShown(DB.profile.show.swim) end
    if ui.jumpBar then ui.jumpBar:SetShown(DB.profile.show.jump) end
  end
  if ui.showHideBtn and ui.showHideBtn.icon then
    ui.showHideBtn.icon:SetDesaturated(DB.profile.hidden and true or false)
  end
  updateFrameHeight()
end

local function buildFrame()
  if ui.frame then return end
  ui.frame = CreateFrame("Frame", "GlitterHealthFrame", UIParent, "BackdropTemplate")
  ui.frame:SetFrameStrata("LOW")
  ui.frame:SetScale(DB.profile.frame.scale)
  ui.frame:SetSize((DB.profile.barWidth or 200) + 20, 200)

  if not DB.profile.frame.x or not DB.profile.frame.y then
    centerFrame(ui.frame)
  else
    ui.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", DB.profile.frame.x, DB.profile.frame.y)
    clampToScreen(ui.frame)
  end

  ui.frame:SetClampedToScreen(true)
  ui.frame:SetClampRectInsets(0, 0, 0, 0)
  ui.frame:SetMovable(true); ui.frame:EnableMouse(true)
  ui.frame:RegisterForDrag("LeftButton")
  ui.frame:SetScript("OnDragStart", function(s) if not DB.profile.frame.locked then s:StartMoving() end end)
  ui.frame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing(); local nx,ny=clampToScreen(s); DB.profile.frame.x,DB.profile.frame.y=nx,ny end)

  ui.barsContainer = CreateFrame("Frame", nil, ui.frame, "BackdropTemplate")
  ui.barsContainer:SetClipsChildren(true)
  ui.barsContainer:SetFrameStrata("LOW")

  local C = DB.profile.colors
  -- Order: Move > Steps > Exercise > Walk > Swim > Jump
  ui.moveBar = mkBar(ui.barsContainer, DB.profile.barWidth, DB.profile.barHeight, C.move)
  ui.stepBar = mkBar(ui.barsContainer, DB.profile.barWidth, DB.profile.barHeight, C.steps)
  ui.exerBar = mkBar(ui.barsContainer, DB.profile.barWidth, DB.profile.barHeight, C.exer)
  ui.walkBar = mkBar(ui.barsContainer, DB.profile.barWidth, DB.profile.barHeight, C.walk)
  ui.swimBar = mkBar(ui.barsContainer, DB.profile.barWidth, DB.profile.barHeight, C.swim)
  ui.jumpBar = mkBar(ui.barsContainer, DB.profile.barWidth, DB.profile.barHeight, C.jump)
  retextureBars()

  
ui.btnsContainer = CreateFrame("Frame", nil, ui.frame, "BackdropTemplate")
ui.btnsContainer:SetHeight(28)

-- Plain text button centered under the bars: "Wellbeing Stats"
ui.wellStatsBtn = CreateFrame("Button", nil, ui.btnsContainer, "UIPanelButtonTemplate")
ui.wellStatsBtn:SetSize(140, 22)
ui.wellStatsBtn:SetText("Wellbeing Stats")
ui.wellStatsBtn:SetScript("OnClick", function() NS.ToggleWellbeing() end)

-- Anchor relative to bars, not just container center
if (DB.profile.buttonsPos or "Bottom") == "Top" then
    ui.wellStatsBtn:SetPoint("BOTTOM", ui.barsContainer, "TOP", 0, 2)  -- above bars
else
    ui.wellStatsBtn:SetPoint("TOP", ui.barsContainer, "BOTTOM", 0, -2) -- below bars
end

  positionButtons()
end

-- ========= wellbeing =========
NS.well = NS.well or {}
local well = NS.well

local affirmations = {
  "You Are Allowed To Take Your Time.","Small Steps Add Up To Real Progress.","You're Worthy Of Care, Exactly As You Are.",
  "Your Effort Today Is Enough.","It's Okay To Rest. Rest Is Productive.","You Are Soft And Strong At The Same Time.",
  "You Don't Have To Be Perfect To Be Loved.","You Belong Here, Fully And Completely.","Your Presence Makes This World Brighter.",
  "You Can Start Over Right Now.","You Deserve Gentleness From Yourself.","You're Learning, And That Matters.",
  "Your Needs Are Valid And Important.","It's Okay To Choose Ease Today.","You've Made It Through Every Tough Day So Far.",
  "You Are Allowed To Take Up Space.","Your Heart Knows What Pace Is Right.","You Are Doing Better Than You Think.",
  "You're Allowed To Celebrate Tiny Wins.","You Can Be A Work In Progress And Still Be Proud.","You're Allowed To Say No And Still Be Kind.",
  "You're Enough, Even On Quiet Days.","You Can Make Gentle Choices That Help Future You.","Being Yourself Is More Than Enough.",
  "You're Allowed To Ask For Support.","You Can Carry Softness Into Strength.","Your Care For Yourself Inspires Others.",
  "Your Story Is Still Being Written.","You Bring Something Special No One Else Can.","You Deserve Comfort And Safety.",
  "You Are Allowed To Be Both Calm And Powerful.","Your Worth Is Not Measured By Productivity.","You're Allowed To Be New At Things.",
  "Today Can Be Simple, And That's Okay.","You Can Choose Kindness Toward Yourself, Again And Again.","You Are Not Behind; You're On Your Path.",
  "Your Curiosity Is A Gift.","You Are Allowed To Be Soft With Yourself.","You Can Trust Your Pace Today.",
  "You Are Doing Your Best With What You Have.","Your Voice Matters Here.","You're Allowed To Learn Slowly.",
  "You Can Make Space For Joy, Even In Small Ways.","Your Boundaries Are Acts Of Care.","You Glow In Your Own Way.",
  "You Can Choose To Breathe And Begin Again.","You Deserve Patience From Yourself.","You Can Rest Without Guilt.",
  "You're Allowed To Choose Comfort Today.","Your Body Deserves Kindness.","You Can Move Gently And Still Move Forward.",
  "You Are Not Alone In This Moment.","You Can Take Breaks And Still Be Brave.","You Deserve Time To Heal.",
  "You Can Hold Hope And Uncertainty Together.","Your Feelings Are Real And Allowed.","You Can Pick One Tiny Win Right Now.",
  "You're Allowed To Make Things Cozy.","You're Allowed To Ask For Easier.","You Can Let Go Of What's Too Heavy.",
  "You Are More Than A To-Do List.","You Can Be Proud Of The Quiet Progress.","You Can Choose Softness As Strength.",
  "You Can Celebrate Showing Up.","You Can Keep Your Heart Tender.","You Can Take Tomorrow Slowly, Too.",
  "You Are Growing In Ways You Can't See Yet.","You Can Tend To Yourself Like A Garden.","You Can Trust The Small Routines.",
  "You Can Be Gentle And Still Unstoppable.","You're Allowed To Enjoy The Little Sparkles.","You Can Set The Pace Today.",
  "You Can Be Exactly Who You Are And Still Be Loved.","You're Allowed To Make Space For Delight.","You Can Choose Rest As Resistance.",
  "You Can Be Messy And Magnificent.","You Can Give Yourself Credit For Trying.","You Can Be Soft With Your Inner Critic.",
  "You're Allowed To Need A Reset.","You Can Unfurl At Your Own Speed.","You Can Keep Choosing You.",
}

local coachTips = {
  "Every Hour: Stand Up For 2 Minutes And Walk Around.","Calf Pumps: Flex And Point Your Feet 20 Times Per Hour.",
  "Ankle Circles: 10 Each Direction Per Leg Every Hour.","Avoid Tight Leg Crossing For Long Periods.",
  "Compression Socks May Help During Long Sessions (Ask Your Doctor).","Chin Tucks: Hold 5s, Repeat 5x To Ease Neck Strain.",
  "Shoulder Rolls: 10 Forward + 10 Backward.","Open-Chest Stretch: Clasp Hands Behind Back, Lift 15s.",
  "Hip Flexor Stretch: 20s Each Side.","Wrist Care: Prayer Stretch 15s, Reverse Prayer 15s.",
  "Forearm Relief: Pull Fingers Back 15s, Switch Sides.","Do 10 Slow Squats During Loading Screens.",
  "Seated Glute Squeezes: 10 Reps.","20-20-20 Rule: Eyes 20ft Away For 20s Every 20 Min.",
  "Blink Intentionally 10 Times To Re-Wet Eyes.","Match Room Light To Screen Brightness.",
  "Keep Water Nearby—Sip Every 15—20 Minutes.","Pair Snacks With Protein + Fiber.",
  "Avoid Heavy Caffeine Late; Protect Sleep.","Chair: Knees Level With Hips, Feet Flat.",
  "Screen: Top At/Just Below Eye Level.","Mouse/Keyboard Close; Wrists Neutral.",
  "Box Breathing 1 Minute (4-4-4-4).","Exhale Longer Than Inhale (4 In, 6 Out).",
  "Keep A Consistent Sleep Window.","Dim Screens The Last Hour Before Bed.",
  "Stand On Every Queue Pop.","Set A 45—60 Minute Mobility Timer.",
  "Micro-Walk: 100 Steps Between Matches.","Neck Yes/No Nods: 10 Gentle Reps.",
  "Spine Reset: Stand, Reach Up Tall, Breathe x3.","Massage Temples 30s To Ease Tension.",
  "Hydration Goal: Finish A Bottle Mid-Session, Refill.","Alternate PTT Hands If Possible.",
  "Keep Ankles Moving When Seated.","Eye Rest: Close Fully For 20s Every 30 Min.",
  "Blue-Light Filter In The Evening.","Hamstring Stretch: 20s Each Leg.",
  "Glute Bridge x10 After Long Sits.","Desk Push-Ups x8 Between Queues.",
  "Seated March 30s To Wake Hips.","Use A Small Lumbar Pillow.",
  "Feet Flat; Use A Footrest If Needed.","Keep A Light Blanket To Relax Shoulders.",
  "Snack Swap: Chips → Nuts + Fruit.","Caffeine Cut-Off ~6 Hours Before Sleep.",
  "Warm Up Hands With A Heat Pack On Cold Days.","Voice Chat Posture: Chin Back, Not Jutting.",
  "Lower In-Game Brightness Slightly To Reduce Glare.","Schedule Real Meals—Don't Only Graze.",
  "If Legs Feel Heavy, Elevate Feet 2—3 Minutes.","Post-Raid Cooldown: 3 Mins Breathing + Stretch.",
}

local live = { steps=nil, milesWalk=nil, milesSwim=nil, jumps=nil, exMin=nil, kcal=nil, vibeFS=nil }

local function refreshLiveStats()
  if not NS.well or not NS.well.frame or not NS.well.frame:IsShown() then return end
  local d = (DB.data and DB.data[DB.today]) or {}
  local E = (d.emotes) or {}
  local S = DB.stats or {}

  -- Today's wins
  if live.steps     then live.steps:SetText(string.format("Steps: %d", safeint(d.steps or 0))) end
  if live.milesWalk then live.milesWalk:SetText(string.format("Walking: %.2f", yd_to_mi(d.distanceFootYd or 0))) end
  if live.jumps     then live.jumps:SetText(string.format("Jumps: %d", safeint(d.jumps or 0))) end
  if live.milesSwim then live.milesSwim:SetText(string.format("Swimming: %.2f", yd_to_mi(d.distanceSwimYd or 0))) end
  if live.exMin     then live.exMin:SetText(string.format("Exercise: %d", safeint((d.exerciseSec or 0)/60))) end
  if live.kcal      then live.kcal:SetText(string.format("Calories: %d", safeint(d.calories or 0))) end

  -- NEW: Today's Vibes
  if live.d_hugs   then live.d_hugs:SetText(string.format("Hugs: %d",   safeint(E.hugs))) end
  if live.d_cheers then live.d_cheers:SetText(string.format("Cheers: %d", safeint(E.cheers))) end
  if live.d_lols   then live.d_lols:SetText(string.format("LOLs: %d",   safeint(E.lols))) end
  if live.d_waves  then live.d_waves:SetText(string.format("Waves: %d", safeint(E.waves))) end
  if live.d_kisses then live.d_kisses:SetText(string.format("Kisses: %d", safeint(E.kisses))) end
  if live.d_dances then live.d_dances:SetText(string.format("Dances: %d", safeint(E.dances))) end
  if live.d_pats   then live.d_pats:SetText(string.format("Pats: %d",   safeint(E.pats))) end
  if live.d_claps  then live.d_claps:SetText(string.format("Claps: %d", safeint(E.claps))) end
  if live.d_boops  then live.d_boops:SetText(string.format("Boops: %d", safeint(E.boops))) end

  -- Lifetime Vibes
  if live.hugs   then live.hugs:SetText(string.format("Total Hugs: %d", safeint(S.hugs))) end
  if live.cheers then live.cheers:SetText(string.format("Total Cheers: %d", safeint(S.cheers))) end
  if live.lols   then live.lols:SetText(string.format("Total LOLs: %d", safeint(S.lols))) end
  if live.waves  then live.waves:SetText(string.format("Total Waves: %d", safeint(S.waves))) end
  if live.kisses then live.kisses:SetText(string.format("Total Kisses: %d", safeint(S.kisses))) end
  if live.dances then live.dances:SetText(string.format("Total Dances: %d", safeint(S.dances))) end
  if live.pats   then live.pats:SetText(string.format("Total Pats: %d", safeint(S.pats))) end
  if live.claps  then live.claps:SetText(string.format("Total Claps: %d", safeint(S.claps))) end
  if live.boops  then live.boops:SetText(string.format("Total Boops: %d", safeint(S.boops))) end

  -- Lifetime totals rollup (unchanged)
  if live.lt_steps or live.lt_foot or live.lt_jumps or live.lt_swim or live.lt_ex or live.lt_kcal then
    local T = (function()
      local t = { steps=0, footYd=0, swimYd=0, jumps=0, exMin=0, kcal=0 }
      for _, dd in pairs(DB.data or {}) do
        t.steps  = t.steps  + safeint(dd.steps or 0)
        t.footYd = t.footYd + (dd.distanceFootYd or 0)
        t.swimYd = t.swimYd + (dd.distanceSwimYd or 0)
        t.jumps  = t.jumps  + safeint(dd.jumps or 0)
        t.exMin  = t.exMin  + safeint((dd.exerciseSec or 0)/60)
        t.kcal   = t.kcal   + safeint(dd.calories or 0)
      end
      return t
    end)()
    if live.lt_steps then live.lt_steps:SetText(string.format("Total Steps: %d", T.steps)) end
    if live.lt_foot  then live.lt_foot:SetText(string.format("Total Walked: %.2f", yd_to_mi(T.footYd))) end
    if live.lt_jumps then live.lt_jumps:SetText(string.format("Total Jumps: %d", T.jumps)) end
    if live.lt_swim  then live.lt_swim:SetText(string.format("Total Swimming: %.2f", yd_to_mi(T.swimYd))) end
    if live.lt_ex    then live.lt_ex:SetText(string.format("Total Exercise: %d", T.exMin)) end
    if live.lt_kcal  then live.lt_kcal:SetText(string.format("Total Calories: %d", T.kcal)) end
  end

  -- Vibe Score (unchanged)
  if live.vibeFS then
    local g = DB.profile.goals
    local pctMove = clamp((d.calories or 0) / math.max(g.calories,    GH_GOAL_MIN.calories),    0, 1)
    local pctSteps= clamp((d.steps or 0)    / math.max(g.steps,       GH_GOAL_MIN.steps),       0, 1)
    local pctEx   = clamp(((d.exerciseSec or 0)/60) / math.max(g.exerciseMin, GH_GOAL_MIN.exerciseMin), 0, 1)
    local pctWalk = clamp(yd_to_mi(d.distanceFootYd or 0) / math.max(g.milesWalk, GH_GOAL_MIN.milesWalk), 0, 1)
    local pctSwim = clamp(yd_to_mi(d.distanceSwimYd or 0) / math.max(g.milesSwim, GH_GOAL_MIN.milesSwim), 0, 1)
    local pctJump = clamp((d.jumps or 0)    / math.max(g.jumps,       GH_GOAL_MIN.jumps),       0, 1)
    local base = (pctMove + pctSteps + pctEx + pctWalk + pctSwim + pctJump) / 6
    local emoteBoost = clamp((safeint(S.hugs)+safeint(S.cheers)+safeint(S.waves)+safeint(S.claps)+safeint(S.boops)) / 120.0, 0, 0.25)
    local pct = math.floor(clamp(base + emoteBoost, 0, 1) * 100 + 0.5)
    live.vibeFS:SetText(colorize(VIBE_HEX, ("Vibe Score: %d%%"):format(pct)))
  end
end

local function buildCSV()
  local rows = {}
  table.insert(rows, "date,steps,miles_walk,miles_swim,miles_total,jumps,exercise_min,calories,hugs_total,cheers_total,lols_total,waves_total,kisses_total,dances_total,pats_total,claps_total,boops_total")
  local dates = {}
  for k,_ in pairs(DB.data) do dates[#dates+1]=k end
  table.sort(dates)
  local S = DB.stats or {}
  for _,dt in ipairs(dates) do
    local d = DB.data[dt] or {}
    local mw = yd_to_mi(d.distanceFootYd or 0)
    local ms = yd_to_mi(d.distanceSwimYd or 0)
    local mt = mw + ms
    local exm = safeint((d.exerciseSec or 0)/60)
    table.insert(rows, string.format("%s,%d,%.3f,%.3f,%.3f,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
      dt, safeint(d.steps), mw, ms, mt, safeint(d.jumps), exm, safeint(d.calories),
      safeint(S.hugs), safeint(S.cheers), safeint(S.lols), safeint(S.waves),
      safeint(S.kisses), safeint(S.dances), safeint(S.pats), safeint(S.claps), safeint(S.boops)))
  end
  return table.concat(rows, "\n")
end

-- Replace your entire openCSVWindow() with this version
local function openCSVWindow()
  if not NS.well.csv then
    local f = CreateFrame("Frame", "GlitterHealthCSV", UIParent, "BackdropTemplate")
    f:SetFrameStrata("DIALOG"); f:SetSize(640, 400)
    f:SetBackdrop({
      bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      edgeSize = 16,
      insets   = {left=4,right=4,top=4,bottom=4}
    })
    f:SetBackdropColor(0,0,0,0.92)
    f:EnableMouse(true); f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) s:StartMoving() end)
    f:SetScript("OnDragStop",  function(s) s:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
    title:SetPoint("TOPLEFT",12,-10)
    title:SetText("|cFFFF77FFGlitterHealth|r — CSV Export")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Inset background for the text area
    local inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate3")
    inset:SetPoint("TOPLEFT", 12, -34)
    inset:SetPoint("BOTTOMRIGHT", -12, 60)

    -- Scrollable, plain edit box (no InputBoxTemplate = no stray border textures)
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -28, 8) -- space for scrollbar

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:ClearFocus()
    edit:SetWidth(scroll:GetWidth()) -- updated below on size change
    edit:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)

    -- so the scrollbar knows its child
    scroll:SetScrollChild(edit)

    -- keep wrapping width correct when the frame is resized
    scroll:SetScript("OnSizeChanged", function(self, w, h)
      edit:SetWidth(w)
    end)

    -- Buttons
    local sel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    sel:SetSize(120, 22)
    sel:SetPoint("BOTTOMLEFT", 14, 18)
    sel:SetText("Select All")
    sel:SetScript("OnClick", function()
      edit:HighlightText()
      edit:SetFocus()
    end)

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    closeBtn:SetSize(100, 22)
    closeBtn:SetPoint("BOTTOMRIGHT", -14, 18)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f.editBox = edit
    NS.well.csv = f
  end

  local f = NS.well.csv
  if NS.well.frame and NS.well.frame:IsShown() then
    f:ClearAllPoints()
    f:SetPoint("LEFT", NS.well.frame, "RIGHT", 12, 0)
  else
    f:ClearAllPoints()
    f:SetPoint("CENTER")
  end

  f.editBox:SetText(buildCSV())
  f:Show()
end

function NS.ToggleWellbeing()
  -- build shell once
  if not well.frame then
    well.frame=CreateFrame("Frame","GlitterHealthWellbeing",UIParent,"BackdropTemplate")
    well.frame:Hide()
    table.insert(UISpecialFrames, "GlitterHealthWellbeing")
    well.frame:SetFrameStrata("LOW")
    well.frame:SetPoint("CENTER")
    well.frame:SetClampedToScreen(true)
    well.frame:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize=16, insets={left=4,right=4,top=4,bottom=4} })
    well.frame:SetBackdropColor(0,0,0,0.9)
    well.frame:EnableMouse(true); well.frame:SetMovable(true)
    well.frame:RegisterForDrag("LeftButton")
    well.frame:SetScript("OnDragStart", function(s) s:StartMoving() end)
    well.frame:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() end)
    local close = CreateFrame("Button", nil, well.frame, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4); close:SetScript("OnClick", function() well.frame:Hide() end)

    local title = well.frame:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
    title:SetPoint("TOPLEFT",12,-10)
    do local fnt, size, flags = title:GetFont(); title:SetFont(fnt, size+6, flags) end
    title:SetText("|cFFFF77FFGlitterHealth|r — Wellbeing")

    local sub = well.frame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT",12,-36)
    sub:SetText("by Kaylissa")

    local exportBtn = CreateFrame("Button", nil, well.frame, "UIPanelButtonTemplate")
    exportBtn:SetSize(100, 22); exportBtn:SetText("Export CSV")
    exportBtn:SetPoint("TOPRIGHT", -40, -12)
    exportBtn:SetScript("OnClick", openCSVWindow)
  end

  if well.frame:IsShown() then
    well.frame:Hide()
    return
  end

  -- rebuild content frame fresh to avoid stacked regions
  if well.content then
    well.content:Hide()
    well.content:SetParent(nil)
    well.content = nil
  end
  well.content = CreateFrame("Frame", nil, well.frame)
  well.content:SetPoint("TOPLEFT", 12, -60)
  well.content:SetPoint("TOPRIGHT", -12, -60)

  live = {}
  well.coachFS = nil
  well.nextTipTime = nil

  local c = well.content
  local y = 0
  local function L(txt, size)
    local fs
    if size == "lg" then fs = c:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
    else fs = c:CreateFontString(nil,"OVERLAY","GameFontHighlight") end
    fs:SetPoint("TOPLEFT", 0, y); fs:SetWidth(480); fs:SetJustifyH("LEFT"); fs:SetText(txt or "")
    y = y - (fs:GetStringHeight() + 8); return fs
  end
  local function H(txt) return L(colorize(SECTION_HEX, txt), "lg") end
  local function Cell(lbl, val, x)
    local left = c:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    left:SetPoint("TOPLEFT", x or 0, y); left:SetWidth(230); left:SetJustifyH("LEFT")
    left:SetText(string.format("%s: %s", lbl, val or "0"))
    return left
  end

  -- Affirmation
  H(colorize(HEADER_HEX, "Daily Affirmation"))
  local playerName = UnitName("player") or "You"
  local daySeed = seedFrom(todayKey() .. ":" .. playerName)
  local affirm = pickFrom(affirmations, daySeed) or "You're Doing Great."
  L(affirm); L(" ")

-- Today's Vibes & Wins
local d = (DB.data and DB.data[DB.today]) or {}
local E = (d.emotes) or {}
local g = DB.profile.goals
local pctMove = clamp((d.calories or 0) / math.max(g.calories,1), 0, 1)
local pctSteps= clamp((d.steps or 0) / math.max(g.steps,1), 0, 1)
local pctEx   = clamp(((d.exerciseSec or 0)/60) / math.max(g.exerciseMin,1), 0, 1)
local pctWalk = clamp(yd_to_mi(d.distanceFootYd or 0) / math.max(g.milesWalk,0.01), 0, 1)
local pctSwim = clamp(yd_to_mi(d.distanceSwimYd or 0) / math.max(g.milesSwim,0.01), 0, 1)
local pctJump = clamp((d.jumps or 0) / math.max(g.jumps,1), 0, 1)
local base = (pctMove + pctSteps + pctEx + pctWalk + pctSwim + pctJump) / 6
local S2 = DB.stats or {}
local emoteBoost = clamp((safeint(S2.hugs)+safeint(S2.cheers)+safeint(S2.waves)+safeint(S2.claps)+safeint(S2.boops)) / 120.0, 0, 0.25)
local vibePct = math.floor(clamp(base + emoteBoost, 0, 1) * 100 + 0.5)

H(colorize(HEADER_HEX, ("Today's Vibes – Vibe Score: %d%%"):format(vibePct)))

-- one continuous table: each row is two stats, left and right
live.d_hugs   = Cell("Hugs", safeint(E.hugs), 0)
live.steps    = Cell("Steps", safeint(d.steps or 0), 260); y = y - 18

live.d_cheers = Cell("Cheers", safeint(E.cheers), 0)
live.jumps    = Cell("Jumps", safeint(d.jumps or 0), 260); y = y - 18

live.d_lols   = Cell("LOLs", safeint(E.lols), 0)
live.exMin    = Cell("Exercise", safeint((d.exerciseSec or 0)/60), 260); y = y - 18

live.d_waves  = Cell("Waves", safeint(E.waves), 0)
live.kcal     = Cell("Calories", safeint(d.calories or 0), 260); y = y - 18

live.d_kisses = Cell("Kisses", safeint(E.kisses), 0)
live.milesWalk= Cell("Walking", yd_to_mi(d.distanceFootYd or 0), 260); y = y - 18

live.d_dances = Cell("Dances", safeint(E.dances), 0)
live.milesSwim= Cell("Swimming", yd_to_mi(d.distanceSwimYd or 0), 260); y = y - 18

live.d_pats   = Cell("Pats", safeint(E.pats), 0)
y = y - 18

live.d_claps  = Cell("Claps", safeint(E.claps), 0)
y = y - 18

live.d_boops  = Cell("Boops", safeint(E.boops), 0)
y = y - 12

-- Lifetime Vibes & Wins
L(" ")
H(colorize(HEADER_HEX, "Lifetime Vibes"))

local S = DB.stats or {}
local T = { steps=0, footYd=0, swimYd=0, jumps=0, exMin=0, kcal=0 }
for _, dd in pairs(DB.data or {}) do
  T.steps  = T.steps  + safeint(dd.steps or 0)
  T.footYd = T.footYd + (dd.distanceFootYd or 0)
  T.swimYd = T.swimYd + (dd.distanceSwimYd or 0)
  T.jumps  = T.jumps  + safeint(dd.jumps or 0)
  T.exMin  = T.exMin  + safeint((dd.exerciseSec or 0)/60)
  T.kcal   = T.kcal   + safeint(dd.calories or 0)
end

-- continuous table, like above
live.hugs     = Cell("Hugs (Total)", safeint(S.hugs), 0)
live.lt_steps = Cell("Steps (Total)", T.steps, 260); y = y - 18

live.cheers   = Cell("Cheers (Total)", safeint(S.cheers), 0)
live.lt_jumps = Cell("Jumps (Total)", T.jumps, 260); y = y - 18

live.lols     = Cell("LOLs (Total)", safeint(S.lols), 0)
live.lt_ex    = Cell("Exercise (Total)", T.exMin, 260); y = y - 18

live.waves    = Cell("Waves (Total)", safeint(S.waves), 0)
live.lt_kcal  = Cell("Calories (Total)", T.kcal, 260); y = y - 18

live.kisses   = Cell("Kisses (Total)", safeint(S.kisses), 0)
live.lt_foot  = Cell("Walking (Total)", yd_to_mi(T.footYd), 260); y = y - 18

live.dances   = Cell("Dances (Total)", safeint(S.dances), 0)
live.lt_swim  = Cell("Swimming (Total)", yd_to_mi(T.swimYd), 260); y = y - 18

live.pats     = Cell("Pats (Total)", safeint(S.pats), 0)
y = y - 18

live.claps    = Cell("Claps (Total)", safeint(S.claps), 0)
y = y - 18

live.boops    = Cell("Boops (Total)", safeint(S.boops), 0)
y = y - 12

  -- Coach tip (rotates every 45s while open)
  L(" ")
  H(colorize(HEADER_HEX, "Coach"))
  well.coachFS = c:CreateFontString(nil,"OVERLAY","GameFontHighlight")
  well.coachFS:SetPoint("TOPLEFT", 0, y)
  well.coachFS:SetWidth(480); well.coachFS:SetJustifyH("LEFT")
  DB.runtime.tipIndex = (DB.runtime.tipIndex or 0) + 1
  local tip = coachTips[((DB.runtime.tipIndex - 1) % #coachTips) + 1] or coachTips[1]
  well.coachFS:SetText(tip)
  y = y - (well.coachFS:GetStringHeight() + 8)
  well.nextTipTime = GetTime() + 45

  local contentHeight = -y + 10
  well.content:SetHeight(contentHeight)
  well.frame:SetWidth(520)
  well.frame:SetHeight(60 + contentHeight + 20)
  well.frame:Show()

  refreshLiveStats()
end

-- ========= bar update & goal FX =========
local function recolorBars()
  if not ui.frame then return end
  local C = DB.profile.colors
  ui.moveBar.bar:SetStatusBarColor(unpack(C.move))
  ui.stepBar.bar:SetStatusBarColor(unpack(C.steps))
  ui.exerBar.bar:SetStatusBarColor(unpack(C.exer))
  ui.walkBar.bar:SetStatusBarColor(unpack(C.walk))
  ui.swimBar.bar:SetStatusBarColor(unpack(C.swim))
  ui.jumpBar.bar:SetStatusBarColor(unpack(C.jump))
  local o = clamp(DB.profile.opacity or 1, 0.0, 1.0)
  for _,h in ipairs({ui.moveBar, ui.stepBar, ui.exerBar, ui.walkBar, ui.swimBar, ui.jumpBar}) do
    if h then
      local r,g,b = h.bar:GetStatusBarColor()
      h.bar:SetStatusBarColor(r,g,b, o)
      h:SetBackdropColor(0,0,0, 0.5 * o)
      h:SetBackdropBorderColor(1,1,1, 0.25 * o)
      h.text:SetAlpha(1.0)
    end
  end
  retextureBars()
end

function retextureBars()
  if not ui or not ui.moveBar then return end
  local path = GH_GetBarTexturePath()
  DB.runtime = DB.runtime or {}
  if DB.runtime._barTexturePath == path then return end -- no change, skip
  for _, holder in ipairs({ ui.moveBar, ui.stepBar, ui.exerBar, ui.walkBar, ui.swimBar, ui.jumpBar }) do
    if holder and holder.bar then
      holder.bar:SetStatusBarTexture(path)
    end
  end
  DB.runtime._barTexturePath = path
end

-- ========= bar update & goal notice =========
local function goalNotify(key, label)
  -- Persist per-day so reload/relog doesn't retrigger
  DB.data = DB.data or {}
  DB.data[DB.today] = DB.data[DB.today] or {}
  DB.data[DB.today].goalsNotified = DB.data[DB.today].goalsNotified or {}

  -- Already celebrated today?
  if DB.data[DB.today].goalsNotified[key] then return end
  DB.data[DB.today].goalsNotified[key] = true

  -- Keep runtime mirrors too (harmless, fast)
  DB.runtime.goalNotified = DB.runtime.goalNotified or {}
  DB.runtime.goalNotified[key] = true

  -- Sound (once per goal/day)
  DB.runtime.levelSoundPlayedT = DB.runtime.levelSoundPlayedT or {}
  if (DB.profile.enableGoalSound ~= false) and not DB.runtime.levelSoundPlayedT[key] then
    if SOUNDKIT and SOUNDKIT.UI_GUILD_LEVEL_UP then PlaySound(SOUNDKIT.UI_GUILD_LEVEL_UP) else PlaySound(888) end
    DB.runtime.levelSoundPlayedT[key] = true
  end

  -- Lightweight top-of-screen notice (your text-only version)
  if (DB.profile.enableCelebration ~= false) and NS and NS.ShowCelebration then
    NS.ShowCelebration(label)
  end

  -- Your new emote + /cheer hook (if present)
  if GH_DoGoalEmotes then GH_DoGoalEmotes(label) end
end

local function updateBars()
  if not ui.frame then buildFrame() end
  local d = getDay(DB, DB.today); local g = DB.profile.goals

  local mv = clamp((d.calories or 0) / math.max(g.calories, GH_GOAL_MIN.calories), 0, 1)
  local st = clamp((d.steps or 0) / math.max(g.steps, GH_GOAL_MIN.steps), 0, 1)
  local ex = clamp(((d.exerciseSec or 0)/60) / math.max(g.exerciseMin, GH_GOAL_MIN.exerciseMin), 0, 1)
  local miW = yd_to_mi(d.distanceFootYd or 0)
  local miS = yd_to_mi(d.distanceSwimYd or 0)
  local jp  = (d.jumps or 0)

  if DB.profile.show.move then
    ui.moveBar.bar:SetValue(mv)
    ui.moveBar.text:SetText(string.format("Move: %d / %d Kcal", safeint(d.calories), g.calories))
  end
  if DB.profile.show.steps then
    ui.stepBar.bar:SetValue(st)
    ui.stepBar.text:SetText(string.format("Steps: %d / %d", safeint(d.steps), g.steps))
  end
  if DB.profile.show.exer then
    ui.exerBar.bar:SetValue(ex)
    ui.exerBar.text:SetText(string.format("Exercise: %d / %d Min", safeint((d.exerciseSec or 0)/60), g.exerciseMin))
  end
  if DB.profile.show.walk then
    ui.walkBar.bar:SetValue(clamp(miW / math.max(g.milesWalk, GH_GOAL_MIN.milesWalk), 0, 1))
    ui.walkBar.text:SetText(string.format("Walk: %0.2f / %0.2f Mi", miW, g.milesWalk))
  end
  if DB.profile.show.swim then
    ui.swimBar.bar:SetValue(clamp(miS / math.max(g.milesSwim, GH_GOAL_MIN.milesSwim), 0, 1))
    ui.swimBar.text:SetText(string.format("Swim: %0.2f / %0.2f Mi", miS, g.milesSwim))
  end
  if DB.profile.show.jump then
    ui.jumpBar.bar:SetValue(clamp((d.jumps or 0) / math.max(g.jumps, GH_GOAL_MIN.jumps), 0, 1))
    ui.jumpBar.text:SetText(string.format("Jumps: %d / %d", safeint(d.jumps), g.jumps))
  end

-- consistent trigger checks (respect GH_GOAL_MIN everywhere)
  if mv >= 1 then goalNotify("move", "Move") end
  if st >= 1 then goalNotify("steps", "Steps") end
  if ex >= 1 then goalNotify("exer", "Exercise") end

  local walkGoal = math.max(g.milesWalk or 0, GH_GOAL_MIN.milesWalk)
  local swimGoal = math.max(g.milesSwim or 0, GH_GOAL_MIN.milesSwim)
  local jumpGoal = math.max(g.jumps or 0, GH_GOAL_MIN.jumps)

  if miW >= walkGoal then goalNotify("walk", "Walk") end
  if miS >= swimGoal then goalNotify("swim", "Swim") end
  if jp  >= jumpGoal then goalNotify("jump", "Jumps") end

  refreshLiveStats()
end

-- movement model
local function estimateMET(speed, inCombat)
  local met=1.5
  if speed>7 then met=9 elseif speed>4 then met=6 elseif speed>0.5 then met=3 end
  if inCombat and met<8 then met=8 end
  return met
end

-- Jump press detection (spacebar); counts on press with throttle, ignores falling
local JUMP_MODE_PRESS = true
local JUMP_PRESS_THROTTLE = 0.8
local function GH_OnJumpPressed()
  if not DB then return end

  -- NEW: block counting while dead/ghost or flying
  if UnitIsDeadOrGhost("player") then
    if DB.profile and DB.profile.debugJumps then
      print("|cFFFF77FFGlitterHealth|r: jump press ignored (dead/ghost)")
    end
    return
  end
  if IsFlying and IsFlying() then
    if DB.profile and DB.profile.debugJumps then
      print("|cFFFF77FFGlitterHealth|r: jump press ignored (flying)")
    end
    return
  end

  -- don't count if already falling
  if IsFalling() then
    if DB.profile and DB.profile.debugJumps then
      print("|cFFFF77FFGlitterHealth|r: jump press ignored (falling)")
    end
    return
  end

  local now = GetTime()
  DB.runtime = DB.runtime or {}
  local last = DB.runtime.lastJumpPress or 0
  if (now - last) < JUMP_PRESS_THROTTLE then
    if DB.profile and DB.profile.debugJumps then
      print("|cFFFF77FFGlitterHealth|r: jump press ignored (throttle)")
    end
    return
  end

  DB.runtime.lastJumpPress = now
  local d = getDay(DB, DB.today)
  d.jumps = (d.jumps or 0) + 1
  if DB.profile and DB.profile.debugJumps then
    print("|cFFFF77FFGlitterHealth|r: jump counted (press)")
  end
end

-- ========= tick (movement, calories, jumps, live updates) =========
local function tick(elapsed)
  local d = getDay(DB, DB.today)

  -- sample Z height for ascent detection (keep ~0.6s history)
  do
    local now = GetTime()
    local _,_,z = UnitPosition("player")
    if z then
      DB.runtime.zHist = DB.runtime.zHist or {}
      table.insert(DB.runtime.zHist, {t=now, z=z})
      local hist = DB.runtime.zHist
      local i = 1
      while i <= #hist do
        if (now - hist[i].t) > 0.6 then
          table.remove(hist, i)
        else
          i = i + 1
        end
      end
    end
  end

  -- NEW: hard guard while dead/ghost: do not accrue movement/exercise/calories
  local isDead = UnitIsDeadOrGhost("player")

  local speed    = GetUnitSpeed("player") or 0
  local moving   = speed > 0.1
  local onTaxi   = UnitOnTaxi("player")
  local inCombat = DB.runtime.inCombat
  local swimming = IsSwimming()
  local mounted  = IsMounted()

  if not isDead then
    if moving or inCombat then
      d.exerciseSec = (d.exerciseSec or 0) + elapsed
    end
    if moving and not onTaxi then
      local delta = speed * elapsed
      if swimming then
        d.distanceSwimYd = (d.distanceSwimYd or 0) + delta
      elseif not mounted then
        d.distanceFootYd = (d.distanceFootYd or 0) + delta
        local stride = DB.profile.stepLengthYd
        local carry  = (DB.runtime.carryStepDist or 0) + delta
        if stride and stride > 0 then
          local add = math.floor(carry / stride)
          if add > 0 then
            d.steps = (d.steps or 0) + add
            carry = carry - add * stride
          end
        end
        DB.runtime.carryStepDist = carry
      end
    end

    -- calories only accrue when alive
    d.calories = (d.calories or 0) + (estimateMET(speed, inCombat) * DB.profile.weightKg * (elapsed / 3600))
  else
    -- While dead/ghost, ensure we don't "bank" partial step distance
    DB.runtime.carryStepDist = 0
  end

-- Jump detection block
if not JUMP_MODE_PRESS then
  -- Early guard: don't track or count while dead/ghost or flying
  if UnitIsDeadOrGhost("player") or (IsFlying and IsFlying()) then
    DB.runtime.airborne = false
    DB.runtime.jumpFallStartTime = nil
    DB.runtime.jumpStartZ = nil
  else
    -- Jump detection (robust): prefer ascent+airtime, with stricter fallback to avoid small ledges
    local falling = IsFalling()
    if falling and not DB.runtime.airborne then
      DB.runtime.airborne = true
      DB.runtime.jumpFallStartTime = GetTime()
      local _,_,z = UnitPosition("player")
      DB.runtime.jumpStartZ = z
    elseif not falling and DB.runtime.airborne then
      local startT  = DB.runtime.jumpFallStartTime or GetTime()
      local airTime = GetTime() - startT
      local _,_,zNow = UnitPosition("player")
      local zStart  = DB.runtime.jumpStartZ or zNow
      local drop    = math.abs((zNow or 0) - (zStart or 0))

      -- compute ascent over ~0.40s before fall start
      local ascent = 0
      do
        local hist  = DB.runtime.zHist or {}
        local prev  = nil
        for i = 1, #hist do
          local e = hist[i]
          if e.t >= (startT - 0.40) and e.t <= startT then
            if prev then
              local dz = (e.z or 0) - (prev.z or 0)
              if dz > 0 then ascent = ascent + dz end
            end
            prev = e
          end
        end
      end

      -- context guards (already blocked flying/dead above)
      local onTaxi2   = UnitOnTaxi("player")
      local mounted2  = IsMounted()
      local swimming2 = IsSwimming()

      -- Tighter thresholds: avoid tiny curb/step-offs
      local AIR_MIN, AIR_MAX = 0.35, 1.20   -- seconds
      local ASC_MIN          = 0.10         -- yards
      local DROP_MAX         = 0.25         -- yards

      local countsAsJump = false
      if (not onTaxi2) and (not mounted2) and (not swimming2) then
        -- primary: ascent + airtime
        if ascent >= ASC_MIN and airTime >= AIR_MIN and airTime <= AIR_MAX then
          countsAsJump = true
        else
          -- fallback: airtime-only, but require small drop to avoid ledges/steps
          local hist = DB.runtime.zHist or {}
          local zOk  = (#hist >= 2) and (DB.runtime.jumpStartZ ~= nil)
          local zTooFlatOrMissing = (ascent < ASC_MIN) or (not zOk)
          if zTooFlatOrMissing and airTime >= AIR_MIN and airTime <= AIR_MAX and (drop <= DROP_MAX) then
            countsAsJump = true
          end
        end
      end

      if countsAsJump then
        d.jumps = (d.jumps or 0) + 1
        if DB.profile.debugJumps then
          print(string.format("|cFFFF77FFGlitterHealth|r: jump! air=%.2f asc=%.3f drop=%.3f", airTime, ascent, drop))
        end
      elseif DB.profile.debugJumps then
        print(string.format("|cFFFF77FFGlitterHealth|r: no-jump air=%.2f asc=%.3f drop=%.3f", airTime, ascent, drop))
      end

      DB.runtime.airborne = false
      DB.runtime.jumpFallStartTime = nil
      DB.runtime.jumpStartZ = nil
    end
  end
end

  if NS.well and NS.well.frame and NS.well.frame:IsShown() then
    if not NS.well.nextTipTime then NS.well.nextTipTime = GetTime() + 45 end
    if GetTime() >= NS.well.nextTipTime then
      DB.runtime.tipIndex = (DB.runtime.tipIndex or 0) + 1
      local ntip = coachTips[((DB.runtime.tipIndex - 1) % #coachTips) + 1] or coachTips[1]
      if NS.well.coachFS then NS.well.coachFS:SetText(ntip) end
      NS.well.nextTipTime = GetTime() + 45
    end
  end

  updateBars()
end



-- ========= utility actions =========
NS.ResetTodayStats = NS.ResetTodayStats or function()
  local tk = todayKey()
  DB.today = tk
  local day = getDay(DB, tk)

  day.calories        = 0
  day.steps           = 0
  day.exerciseSec     = 0
  day.distanceFootYd  = 0
  day.distanceSwimYd  = 0
  day.jumps           = 0
  day.goalsNotified   = {}   -- <-- clear daily celebration flags

  DB.runtime.goalNotified     = {}
  DB.runtime.levelSoundPlayedT= {}

  if NS and NS.RefreshUI then pcall(NS.RefreshUI) end
  if updateBars then pcall(updateBars) end
  print("|cFFFF77FFGlitterHealth|r: Today's stats reset.")
end

function NS.TestCelebration()
  -- just trigger the same text notice as a real goal would
  NS.ShowCelebration("Test")
end

-- ========= celebration notice (single, big magenta) =========
NS.ShowCelebration = NS.ShowCelebration or function(goalLabel)
  goalLabel = goalLabel or "Goal Complete!"
  local msg = string.format("GlitterHealth: %s Goal Reached!", goalLabel)

  -- Big top-center banner using RaidWarningFrame
  if RaidNotice_AddMessage and RaidWarningFrame then
    -- custom magenta color
    local color = { r = 1.0, g = 0.2, b = 1.0 }  -- bright magenta
    RaidNotice_AddMessage(RaidWarningFrame, msg, color)
  else
    -- fallback to chat if for some reason frame missing
    print("|cFFFF33FFGlitterHealth|r: "..msg)
  end
end

-- ========= settings UI (2-column sections) =========
local SettingsUtil = {}
do
  local function buildCanvas()
    local canvas=CreateFrame("Frame"); canvas.name="GlitterHealth"; canvas:Hide()
    local scroll = CreateFrame("ScrollFrame", nil, canvas, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8); scroll:SetPoint("BOTTOMRIGHT", -30, 8)
    local content = CreateFrame("Frame", nil, scroll); content:SetWidth(560); content:SetHeight(1)
    scroll:SetScrollChild(content)
    local y = -8
    local title = content:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 12, y); title:SetText("|cFFFF77FFGlitterHealth|r Options")
    y = y - 28

    local function header(text) local fs=content:CreateFontString(nil,"OVERLAY","GameFontHighlightLarge"); fs:SetPoint("TOPLEFT",12,y); fs:SetText(text); y=y-26 end
    local function sectionStart()
      local f = CreateFrame("Frame", nil, content)
      f:SetPoint("TOPLEFT", 12, y); f:SetSize(560 - 24, 10)
      f.leftX = 0; f.rightX = 270 + 24; f.leftY = 0; f.rightY = 0
      return f
    end
    local function place(sec, side, height)
      if side=="left" then local off=-sec.leftY; sec.leftY=sec.leftY+height; return sec.leftX, off
      else local off=-sec.rightY; sec.rightY=sec.rightY+height; return sec.rightX, off end
    end
    local function sectionFinish(sec) local used=math.max(sec.leftY,sec.rightY); y=y - used - 6 end
    local function label(parent, text, x, yOff) local fs=parent:CreateFontString(nil,"OVERLAY","GameFontHighlight"); fs:SetPoint("TOPLEFT",x,yOff); fs:SetText(text); return fs end
    local dd_id, sl_id = 0,0
    local function dropdown(sec, side, lbl, items, get, set)
      local x,yOff = place(sec, side, 64)
      label(sec,lbl,x,yOff)
      dd_id=dd_id+1; local dd=CreateFrame("Frame","GlitterHealthDD"..dd_id,sec,"UIDropDownMenuTemplate")
      dd:SetPoint("TOPLEFT", x-16, yOff-18); UIDropDownMenu_SetWidth(dd, 250)
      UIDropDownMenu_Initialize(dd, function(self, level)
        for _,name in ipairs(items) do local info=UIDropDownMenu_CreateInfo()
          info.text=name; info.func=function() set(name); UIDropDownMenu_SetSelectedName(dd,name) end
          info.checked=(get()==name); UIDropDownMenu_AddButton(info, level) end
      end)
      UIDropDownMenu_SetSelectedName(dd, get())
    end
    local function slider(sec, side, lbl, minv, maxv, step, get, set, fmtLow, fmtHigh)
  local x,yOff = place(sec, side, 74)
  label(sec, lbl, x, yOff)
  sl_id=sl_id+1; local name="GlitterHealth_Slider_"..sl_id
  local s=CreateFrame("Slider",name,sec,"OptionsSliderTemplate"); s:SetPoint("TOPLEFT",x,yOff-18); s:SetWidth(260)
  s:SetMinMaxValues(minv,maxv); s:SetValueStep(step); s:SetObeyStepOnDrag(true); s:SetValue(get())
  local low=_G[name.."Low"]; local high=_G[name.."High"]
  if low then low:SetText(string.format(fmtLow or "%.2f", minv)) end
  if high then high:SetText(string.format(fmtHigh or "%.2f", maxv)) end

  -- Value box below the slider (like your screenshot)
  local eb = CreateFrame("EditBox", nil, sec, "InputBoxTemplate")
  eb:SetAutoFocus(false); eb:SetWidth(60); eb:SetHeight(20)
  eb:SetPoint("TOP", s, "BOTTOM", 0, -8)

  local function fmtValue(v)
    if string.find(string.lower(lbl), "opacity") then
      return tostring(math.floor((v or 0)*100 + 0.5)).."%"
    elseif (step or 0) >= 1 then
      return string.format("%d", v)
    else
      return string.format("%.2f", v)
    end
  end

  local function parseValue(t)
    t = tostring(t or "")
    t = t:gsub("%%","")
    local v = tonumber(t)
    if not v then return get() end
    if string.find(string.lower(lbl), "opacity") then v = v/100 end
    if v < minv then v = minv elseif v > maxv then v = maxv end
    if (step or 0) > 0 then v = math.floor((v/step) + 0.5) * step end
    return v
  end

  eb:SetText(fmtValue(get()))

  s:SetScript("OnValueChanged", function(_, v)
    set(v)
    eb:SetText(fmtValue(v))
  end)

  eb:SetScript("OnEnterPressed", function(self)
    local v = parseValue(self:GetText())
    s:SetValue(v) -- triggers set() via OnValueChanged
    self:ClearFocus()
  end)
  eb:SetScript("OnEditFocusLost", function(self)
    self:SetText(fmtValue(s:GetValue()))
  end)
end
    local function check(sec, side, lbl, tip, get, set)
      local x,yOff = place(sec, side, 32)
      local cb=CreateFrame("CheckButton", nil, sec, "InterfaceOptionsCheckButtonTemplate")
      cb:SetPoint("TOPLEFT", x, yOff); cb.Text:SetText(lbl); cb.tooltipText=lbl; cb.tooltipRequirement=tip
      cb:SetChecked(get()); cb:SetScript("OnClick", function(s) set(s:GetChecked()) end)
    end
    local function edit(sec, side, lbl, tip, width, get, set)
      local x,yOff = place(sec, side, 46); label(sec, lbl, x, yOff)
      local eb=CreateFrame("EditBox", nil, sec, "InputBoxTemplate")
      eb:SetAutoFocus(false); eb:SetSize(width or 120, 24); eb:SetPoint("TOPLEFT", x, yOff-18)
      eb:SetText(tostring(get())); eb:SetCursorPosition(0)
      eb:SetScript("OnEnterPressed", function(s) local v=tonumber(s:GetText()); if v then set(v) end; s:ClearFocus(); s:SetText(tostring(get())) end)
      eb:SetScript("OnEditFocusLost", function(s) s:SetText(tostring(get())) end)
    end
    local function button(sec, side, text, onClick)
      local x,yOff = place(sec, side, 34)
      local b=CreateFrame("Button", nil, sec, "UIPanelButtonTemplate")
      b:SetSize(140, 22); b:SetPoint("TOPLEFT", x, yOff); b:SetText(text); b:SetScript("OnClick", onClick); return b
    end

    -- Appearance
    header("Appearance")
    local names = {} for k,_ in pairs(THEMES) do names[#names+1]=k end table.sort(names)
    local secA = sectionStart()
    dropdown(secA,"left","Color Theme",names,function() return DB.profile.theme end,function(v) applyTheme(v); recolorBars() end)
    dropdown(secA,"right","Buttons Position",{"Bottom","Top"},function() return DB.profile.buttonsPos end,function(v) DB.profile.buttonsPos=v; positionButtons() end)
    
    -- LibSharedMedia: Bar Texture picker
    do
      local function listTextures()
        local list = { "Blizzard" }
        if LSM and LSM.List then
          local l = LSM:List("statusbar") or {}
          for i = 1, #l do list[#list+1] = l[i] end
        end
        table.sort(list, function(a,b) return a:lower() < b:lower() end)
        return list
      end
      local texItems = listTextures()
      dropdown(
        secA, "left", "Bar Texture", texItems,
        function() return (DB.profile.barTexture or "Blizzard") end,
        function(name)
          DB.profile.barTexture = name or "Blizzard"
          retextureBars()
        end
      )
    end
    
        slider(secA,"right","Bar Height",12,30,1,function() return DB.profile.barHeight or 18 end,function(v) DB.profile.barHeight=clamp(math.floor(v+0.5),12,30); for _,h in ipairs({ui.moveBar, ui.stepBar, ui.exerBar, ui.walkBar, ui.swimBar, ui.jumpBar}) do if h then local w = h:GetWidth() or (DB.profile.barWidth or 200); h:SetSize(w, DB.profile.barHeight) end end; relayoutBars(); updateFrameHeight() end,"%d","%d")
    slider(secA,"right","Bars Width",160,360,2,function() return DB.profile.barWidth end,function(v) DB.profile.barWidth=math.floor(v+0.5); ui.frame:SetWidth(DB.profile.barWidth+20); for _,h in ipairs({ui.moveBar, ui.stepBar, ui.exerBar, ui.walkBar, ui.swimBar, ui.jumpBar}) do if h then h:SetWidth(DB.profile.barWidth) end end; positionButtons() end,"%d","%d")
    slider(secA,"left","Bar Gap",-6,8,1,function() return DB.profile.barGap or 0 end,function(v) DB.profile.barGap=clamp(math.floor(v+0.5),-6,8); relayoutBars() end,"%d","%d")
    slider(secA,"right","Bars Opacity",0.00,1.00,0.01,function() return DB.profile.opacity end,function(v) DB.profile.opacity=round(v,2); recolorBars() end,"%.2f","%.2f")
    slider(secA,"left","Scale",0.70,1.50,0.01,function() return DB.profile.frame.scale end,function(v) DB.profile.frame.scale=round(v,2); if ui.frame then ui.frame:SetScale(DB.profile.frame.scale); local nx,ny=clampToScreen(ui.frame); DB.profile.frame.x,DB.profile.frame.y=nx,ny end end,"%.2f","%.2f")
    button(secA,"right","Center Window",function() if not ui.frame then buildFrame() end centerFrame(ui.frame); print("|cFFFF77FFGlitterHealth|r: Window Centered.") end)
    check (secA,"left","Lock Frame","Prevents dragging the panel.",function() return DB.profile.frame.locked end,function(v) DB.profile.frame.locked = not not v end)
    
    sectionFinish(secA)

    -- Bars Shown
    header("Bars Shown")
    local secB = sectionStart()
    local function tog(key) return function() return DB.profile.show[key] end,
      function(v) DB.profile.show[key]=not not v; relayoutBars(); updateBars() end end
    check(secB,"left","Move (Calories)",nil,tog("move"));  check(secB,"right","Steps",nil,tog("steps"))
    check(secB,"left","Exercise Minutes",nil,tog("exer")); check(secB,"right","Walk Miles",nil,tog("walk"))
    check(secB,"left","Swim Miles",nil,tog("swim"));       check(secB,"right","Jumps",nil,tog("jump"))
    sectionFinish(secB)

-- Goals
header("Goals")
local secC = sectionStart()

-- Move (Calories)
slider(secC,"left","Move Goal (Kcal)", 1, 3000, 1,
  function() return math.floor((DB.profile.goals.calories or 500) + 0.5) end,
  function(v) DB.profile.goals.calories = math.max(1, math.floor(v + 0.5)) end,
  "%d","%d")

-- Steps
slider(secC,"right","Steps Goal", 1, 50000, 1,
  function() return math.floor((DB.profile.goals.steps or 20000) + 0.5) end,
  function(v) DB.profile.goals.steps = math.max(1, math.floor(v + 0.5)) end,
  "%d","%d")

-- Exercise Minutes
slider(secC,"left","Exercise Goal (Min)", 1, 240, 1,
  function() return math.floor((DB.profile.goals.exerciseMin or 45) + 0.5) end,
  function(v) DB.profile.goals.exerciseMin = math.max(1, math.floor(v + 0.5)) end,
  "%d","%d")

-- Walk Miles
slider(secC,"right","Walk Miles Goal", 0.1, 20.0, 0.1,
  function() return round(DB.profile.goals.milesWalk or 5.0, 2) end,
  function(v) DB.profile.goals.milesWalk = math.max(0.1, round(v, 2)) end,
  "%.2f","%.2f")

-- Swim Miles
slider(secC,"left","Swim Miles Goal", 0.1, 10.0, 0.1,
  function() return round(DB.profile.goals.milesSwim or 1.0, 2) end,
  function(v) DB.profile.goals.milesSwim = math.max(0.1, round(v, 2)) end,
  "%.2f","%.2f")

-- Jumps
slider(secC,"right","Jumps Goal", 1, 10000, 1,
  function() return math.floor((DB.profile.goals.jumps or 1000) + 0.5) end,
  function(v) DB.profile.goals.jumps = math.max(1, math.floor(v + 0.5)) end,
  "%d","%d")

sectionFinish(secC)

-- Notifications
header("Notifications")
local secN = sectionStart()
check (secN,"left","Play Goal Sound","Plays the level-up sound the first time you hit a goal each day.",
  function() return DB.profile.enableGoalSound ~= false end,
  function(v) DB.profile.enableGoalSound = v and true or false end)
check (secN,"right","Show Goal Notice",
  "Shows a top-of-screen text notice when a goal is reached.",
  function() return DB.profile.enableCelebration ~= false end,
  function(v) DB.profile.enableCelebration = v and true or false end)
button(secN,"left","Reset Today's Stats", function() NS.ResetTodayStats() end)
button(secN,"right","Test Goal",   function() NS.TestCelebration() end)
sectionFinish(secN)


    content:SetHeight(-y + 20)
    if Settings and Settings.RegisterCanvasLayoutCategory then
      local cat=Settings.RegisterCanvasLayoutCategory(canvas,"GlitterHealth"); cat.ID="GlitterHealthCategory"; Settings.RegisterAddOnCategory(cat); return cat
    else
      canvas.name="GlitterHealth"; if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(canvas) end; return { ID="GlitterHealthLegacy" }
    end
  end

  function SettingsUtil:Build()
    if self._built then return end
    self.category = buildCanvas()
    self._built = true
  end
  function SettingsUtil:Open()
    self:Build()
    if Settings and Settings.RegisterCanvasLayoutCategory and self.category and self.category.ID then
      Settings.OpenToCategory(self.category.ID)
    elseif InterfaceOptionsFrame_OpenToCategory then
      InterfaceOptionsFrame_OpenToCategory("GlitterHealth")
    end
  end
end

-- ========= emote tracking =========
local function initStats()
  DB.stats = DB.stats or {}
  local s=DB.stats
  s.hugs = s.hugs or 0; s.cheers=s.cheers or 0; s.lols=s.lols or 0; s.waves=s.waves or 0
  s.kisses=s.kisses or 0; s.dances=s.dances or 0; s.pats=s.pats or 0; s.claps=s.claps or 0; s.boops=s.boops or 0
end

local trackedEmotes = {
  { key="hugs",   patterns={"hug","hugs"} },
  { key="cheers", patterns={"cheer","cheers"} },
  { key="lols",   patterns={"laugh","laughs","lol"} },
  { key="waves",  patterns={"wave","waves"} },
  { key="kisses", patterns={"kiss","kisses","blows a kiss"} },
  { key="dances", patterns={"dance","dances"} },
  { key="pats",   patterns={"pat","pats"} },
  { key="claps",  patterns={"clap","claps","applaud","applauds"} },
  { key="boops",  patterns={"boop","boops"} },
}

local function onEmoteMessage(event, msg, sender)
  if not msg then return end
  local me = UnitName("player")
  local mlow = msg:lower()
  local involvesMe =
      (sender == me)
      or (me and mlow:find(me:lower(), 1, true) ~= nil)
      or (mlow:find(" you[ %.!%?,]") ~= nil)      -- "... hugs you."
      or (mlow:match("^you ") ~= nil)             -- "You wave."
  if not involvesMe then return end

  -- ensure today's bucket exists
  local day = getDay(DB, DB.today)
  day.emotes = day.emotes or {}
  
  for _,e in ipairs(trackedEmotes) do
    for _,p in ipairs(e.patterns) do
      if string.find(mlow, p, 1, true) then
        -- lifetime
        DB.stats[e.key] = safeint(DB.stats[e.key] or 0) + 1
        -- NEW: today
        day.emotes[e.key] = safeint(day.emotes[e.key] or 0) + 1
        refreshLiveStats()
        return
      end
    end
  end
end

-- ========= core/events =========
local function applyRaceDefaultsIfNeeded()
  local stride, wt, race, sex = getRaceSexDefaults()
  if not DB.profile._appliedRace or DB.profile._appliedRace~=race or DB.profile._appliedSex~=sex then
    DB.profile.stepLengthYd = stride; DB.profile.weightKg = wt
    DB.profile._appliedRace, DB.profile._appliedSex = race, sex
  end
end

local function recolorApplyAndPosition()
  applyTheme(DB.profile.theme or "Candy")
  positionButtons()
  relayoutBars()
  updateBars()
end

local core=CreateFrame("Frame")
core:SetScript("OnEvent", function(self, event, arg1, arg2)
  if event=="ADDON_LOADED" and arg1==ADDON_NAME then
    if not _G.GlitterHealthDB then _G.GlitterHealthDB = {} end
    DB = _G.GlitterHealthDB
    copyInto(DB, defaults)
    ensureColorsTable()
    GH_ClampGoals()
    if JUMP_MODE_PRESS and hooksecurefunc then
      hooksecurefunc("JumpOrAscendStart", GH_OnJumpPressed)
    end
    if DB.version ~= DB_VERSION then DB.version = DB_VERSION end
    DB.today = (DB.today and DB.today ~= "") and DB.today or todayKey()
    DB.runtime.goalNotified = {}
    applyRaceDefaultsIfNeeded()
    initStats()
    SettingsUtil:Build()
    buildFrame()
    recolorApplyAndPosition()
    GH_PreMarkTodayGoals()

elseif event=="PLAYER_LOGIN" then
  DB.runtime.airborne = IsFalling() or false
  C_Timer.After(0.2, function()
    if ui.frame then
      local nx,ny = clampToScreen(ui.frame)
      DB.profile.frame.x, DB.profile.frame.y = nx, ny
    end
    print("|cFFFF77FFGlitterHealth loaded!|r")
  end)

  local ACCUM = 0
  local TICK_DT = 0.10  -- 10Hz; tweak to taste

  self:SetScript("OnUpdate", function(_, elapsed)
    local tk = todayKey()
    if tk ~= DB.today then
      DB.today = tk
      DB.runtime.carryStepDist = 0
      DB.runtime.goalNotified = {}
      DB.runtime.levelSoundPlayedT = {}
      GH_PreMarkTodayGoals()
      GH_ClampGoals()
    end

    ACCUM = ACCUM + (elapsed or 0)
    if ACCUM < TICK_DT then return end
    local step = ACCUM; ACCUM = 0
    pcall(function() tick(step) end)
  end)

  elseif event=="PLAYER_REGEN_DISABLED" then DB.runtime.inCombat=true
  elseif event=="PLAYER_REGEN_ENABLED"  then DB.runtime.inCombat=false
  elseif event=="PLAYER_ENTERING_WORLD" then DB.runtime.inCombat=InCombatLockdown()
  elseif event=="CHAT_MSG_TEXT_EMOTE" or event=="CHAT_MSG_EMOTE" then
    onEmoteMessage(event, arg1, arg2)
  end
end)
core:RegisterEvent("ADDON_LOADED")
core:RegisterEvent("PLAYER_LOGIN")
core:RegisterEvent("PLAYER_ENTERING_WORLD")
-- ========= version check (addon comms) =========
local __gh_VC = { prefix = "GH_VER1" }
__gh_VC.seenNewer = {}
__gh_VC.lastPing = 0

local function __gh_vcSend(where, msg, target)
  if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered and not C_ChatInfo.IsAddonMessagePrefixRegistered(__gh_VC.prefix) then
    C_ChatInfo.RegisterAddonMessagePrefix(__gh_VC.prefix)
  end
  if C_ChatInfo then
    C_ChatInfo.SendAddonMessage(__gh_VC.prefix, msg, where, target)
  end
end

local function __gh_vcPing()
  local now = GetTime()
  if (now - (__gh_VC.lastPing or 0)) < 8 then return end
  __gh_VC.lastPing = now
  local ver = NS.VERSION or "0.0.0"
  if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then __gh_vcSend("INSTANCE_CHAT", "PING:"..ver) end
  if IsInRaid() then __gh_vcSend("RAID", "PING:"..ver)
  elseif IsInGroup() then __gh_vcSend("PARTY", "PING:"..ver) end
  if IsInGuild() then __gh_vcSend("GUILD", "PING:"..ver) end
end

local function __gh_vcOnAddonMsg(prefix, msg, channel, sender)
  if prefix ~= __gh_VC.prefix then return end
  local who = Ambiguate(sender or "?", "guild")
  local their = msg:match("^PING:(.+)$") or msg:match("^VERS:(.+)$")
  if not their then return end
  if msg:find("^PING:") then
    __gh_vcSend("WHISPER", "VERS:"..(NS.VERSION or "0.0.0"), sender)
  end
  if __gh_isNewer(their, NS.VERSION or "0.0.0") and not __gh_VC.seenNewer[who] then
    __gh_VC.seenNewer[who] = true
    print(string.format("|cFFFF77FFGlitterHealth|r: A newer version is available (%s has v%s, you have v%s).",
      who or "someone", their, NS.VERSION or "0.0.0"))
  end
end

-- hook into events (wrap existing OnEvent to preserve behavior)
if core and core.RegisterEvent then
  core:RegisterEvent("GROUP_ROSTER_UPDATE")
  core:RegisterEvent("GUILD_ROSTER_UPDATE")
  core:RegisterEvent("PLAYER_ENTERING_WORLD")
  core:RegisterEvent("CHAT_MSG_ADDON")
  local __old = core:GetScript("OnEvent")
  core:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
      __gh_vcOnAddonMsg(...)
    elseif event == "GROUP_ROSTER_UPDATE" or event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
      C_Timer.After(3, __gh_vcPing)
    end
    if __old then pcall(__old, self, event, ...) end
  end)
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(__gh_VC.prefix)
  end
end

-- slash to force a ping
SLASH_GLITTERHEALTHVER1 = "/ghver"
SlashCmdList["GLITTERHEALTHVER"] = function()
  print("|cFFFF77FFGlitterHealth|r: Version "..(NS.VERSION or "0.0.0")..". Pinging group/guild...")
  __gh_vcPing()
end
-- ===============================================
core:RegisterEvent("PLAYER_REGEN_DISABLED")
core:RegisterEvent("PLAYER_REGEN_ENABLED")
core:RegisterEvent("CHAT_MSG_TEXT_EMOTE")
core:RegisterEvent("CHAT_MSG_EMOTE")

-- ========= slash =========
SLASH_GLITTERHEALTH1 = "/glitterhealth"
SLASH_GLITTERHEALTH2 = "/gh"
SlashCmdList["GLITTERHEALTH"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "" or msg == "help" or msg == "?" then
    NS.PrintGHHelp()

  elseif msg == "lock" then
    DB.profile.frame.locked = true
    print(GH_tag("GlitterHealth: ").."Frame Locked.")

  elseif msg == "unlock" then
    DB.profile.frame.locked = false
    print(GH_tag("GlitterHealth: ").."Frame Unlocked. Drag me!")

  elseif msg == "reset" then
    DB.data[DB.today] = nil
    DB.runtime.carryStepDist = 0
    updateBars()
    print(GH_tag("GlitterHealth: ").."Today Reset.")

  elseif msg == "mood" or msg == "well" or msg == "wellbeing" then
    NS.ToggleWellbeing()

  elseif msg == "options" or msg == "opt" or msg == "settings" then
    if SettingsUtil and SettingsUtil.Open then SettingsUtil:Open() end

  elseif msg == "hide" then
    setHidden(true)
    print(GH_tag("GlitterHealth: ").."Bars Hidden. Use "..GH_tag("/gh show")..GH_dim(" to show."))

  elseif msg == "show" then
    setHidden(false)
    print(GH_tag("GlitterHealth: ").."Bars Shown.")

  elseif msg == "debugjumps" then
    DB.profile.debugJumps = not DB.profile.debugJumps
    print(GH_tag("GlitterHealth: ").."Jump debug "..(DB.profile.debugJumps and "ON" or "OFF")..".")

  elseif msg == "export" or msg == "csv" then
    if openCSVWindow then openCSVWindow() end

  elseif msg == "center" then
    if not ui.frame then buildFrame() end
    centerFrame(ui.frame)
    print(GH_tag("GlitterHealth: ").."Window Centered.")

  elseif msg == "ver" or msg == "version" then
    print(GH_tag("GlitterHealth: ").."Version "..(NS.VERSION or "?")..". Pinging group/guild…")
    if type(__gh_vcPing) == "function" then __gh_vcPing() end

  else
    -- unknown subcommand → help
    NS.PrintGHHelp()
  end

  updateBars()
end