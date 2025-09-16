-- UI for searching maps, POIs and friends.
local AZEROTH_MAPS, AM = ...
local DBG = AM.DBG
local searchMaps = AM.searchMaps
local searchFriends = AM.searchFriends
local openMapForRecord = AM.openMapForRecord

local Dungeons = _G.Dungeons and _G.Dungeons.recs
local dungeonLookup = {}
if Dungeons then
  for id, rec in pairs(Dungeons) do
    dungeonLookup[id] = true
    if rec.name then
      dungeonLookup[rec.name:lower()] = true
    end
  end
end

local function isDungeon(rec)
  if not rec then return false end
  if rec.mapID and dungeonLookup[rec.mapID] then return true end
  if rec.name and dungeonLookup[rec.name:lower()] then return true end
  return false
end

local COLOR_AREA    = "|cffFF6B00"
local COLOR_POI     = "|cffFFEB00"
local COLOR_DUNGEON = "|cffB300FF"

-- Return a localized expansion name for the given id (0 = Classic, 1 = TBC, ...).
-- Returns nil when the id is outside the valid EJ tier range.
local function expansionName(id)
  if type(id) ~= "number" or id < 0 then
    return nil
  end

  local tierIndex = id + 1
  local numTiers = EJ_GetNumTiers and EJ_GetNumTiers() or 0
  if tierIndex < 1 or tierIndex > numTiers then
    return nil
  end

  EJ_SelectTier(tierIndex)
  local name = EJ_GetTierInfo(tierIndex)
  return name
end

-- Helper: get numeric expansion id (or +inf if unknown so it sorts last)
local function getExpansionId(rec)
  if not rec then return math.huge end
  local e = rec.expansion_id
  if e == nil and type(rec.timeline) == "table" then
    e = rec.timeline.expansion
  end
  if type(e) ~= "number" then return math.huge end
  return e
end

local function variantLabel(rec)
  if not rec then return "" end
  local parts = {}
  if rec.instance_type then table.insert(parts, rec.instance_type) end
  if rec.type and rec.type ~= "map" and rec.type ~= "poi" then table.insert(parts, rec.type) end
  local exp
  if rec.expansion_id and rec.expansion_id >= 0 then
    exp = rec.expansion_id
  elseif rec.timeline and rec.timeline.expansion and rec.timeline.expansion >= 0 then
    exp = rec.timeline.expansion
  end
  if exp and exp >= 0 then
    local name = expansionName(exp)
    if name then
      table.insert(parts, string.format("%d. %s", exp + 1, name))
    else
      table.insert(parts, tostring(exp + 1))
    end
  end
  if rec.timeline then
    local tparts = {}
    if rec.timeline.min and rec.timeline.max then
      table.insert(tparts, string.format("%d-%d", rec.timeline.min, rec.timeline.max))
    elseif rec.timeline.min then
      table.insert(tparts, string.format("%d+", rec.timeline.min))
    elseif rec.timeline.max then
      table.insert(tparts, string.format("-%d", rec.timeline.max))
    end
    if #tparts > 0 then
      table.insert(parts, "Timeline: " .. table.concat(tparts, " "))
    end
  end
  if rec.phase_id then table.insert(parts, "Phase " .. tostring(rec.phase_id)) end
  if rec.phase_group then table.insert(parts, "Phase Group " .. tostring(rec.phase_group)) end
  return table.concat(parts, " | ")
end

local function cloneRecord(rec)
  local t = {}
  for k, v in pairs(rec or {}) do
    if k == "variants" then
      -- variants are handled separately
    elseif k == "timeline" and type(v) == "table" then
      local tl = {}
      for tk, tv in pairs(v) do tl[tk] = tv end
      t.timeline = tl
    else
      t[k] = v
    end
  end
  return t
end

local function expansionKey(rec)
  if rec.timeline then
    if type(rec.timeline) == "table" then
      if rec.timeline.expansion then
        return "e:" .. tostring(rec.timeline.expansion)
      end
      local parts = {}
      for k, v in pairs(rec.timeline) do parts[#parts+1] = tostring(k) .. "=" .. tostring(v) end
      table.sort(parts)
      return "t:" .. table.concat(parts, ",")
    end
    return "t:" .. tostring(rec.timeline)
  end
  return "e:" .. tostring(rec.expansion_id or 0)
end

local function handleVariantClick(rec)
  DBG("variant click: %s", rec and rec.name or "<nil>")
  openMapForRecord(rec)
  if AM.variantDropdown then AM.variantDropdown:Hide() end
  if AM.searchBox then
    AM.searchBox:SetText("")
    AM.searchBox:ClearFocus()
  end
end

local function showVariantMenu(rec)
  if not rec then return end
  DBG("showVariantMenu: %s with %d variant(s)", rec.name or "<nil>", #(rec.variants or {}))
  -- Preserve the canonical primary record as option 1; sort the rest.
  local primary = cloneRecord(rec)
  local list, seen = {}, {}
  local function add(r)
    if not r then return end
    local copy = cloneRecord(r)
    local unfiltered = (copy.type == "poi" and AM.filterPOIs == false) or (copy.type ~= "poi" and AM.filterAreas == false)
    if unfiltered then
      table.insert(list, copy)
      return
    end
    local ids = {}
    local expKey = expansionKey(copy)
    if copy.type ~= "poi" and not copy.poiID then
      if copy.areaID then
        ids[#ids+1] = expKey .. ":a" .. copy.areaID
        ids[#ids+1] = expKey .. ":m" .. copy.areaID
      end
      if copy.mapID then
        ids[#ids+1] = expKey .. ":m" .. copy.mapID
        ids[#ids+1] = expKey .. ":a" .. copy.mapID
      end
    else
      if copy.poiID then ids[#ids+1] = expKey .. ":p" .. copy.poiID end
    end
    local existing
    for _, k in ipairs(ids) do
      existing = seen[k]
      if existing then break end
    end
    if existing then
      for k, v in pairs(copy) do
        if existing[k] == nil then existing[k] = v end
      end
    else
      for _, k in ipairs(ids) do seen[k] = copy end
      table.insert(list, copy)
    end
  end
  -- Collect only variants (the primary stays pinned at index 1)
  for _, v in ipairs(rec.variants or {}) do add(v) end
  -- Sort variants by expansion id (ascending), then by label as a tiebreaker
  table.sort(list, function(b, a)
    local ea, eb = getExpansionId(a), getExpansionId(b)
    if ea ~= eb then return ea < eb end
    -- tie-breaker using map/area/name so ordering is stable
    local la = mapLabel and mapLabel(a) or (a.display or a.name or "")
    local lb = mapLabel and mapLabel(b) or (b.display or b.name or "")
    return tostring(la) < tostring(lb)
  end)
  -- Prepend primary and label entries
  local full = { primary }
  for i, r in ipairs(list) do full[#full+1] = r end
  for i, r in ipairs(full) do
    local d = variantLabel(r)
    r.display = (d ~= "" and d) or (i == 1 and "Default" or "Variant")
  end
  AM.results = full
  AM.suppressSearch = true
  if AM.variantDropdown then
    DBG("showVariantMenu: displaying %d option(s)", #full)
    AM.variantDropdown:ShowResults(full)
  end
  AM.suppressSearch = false
end

local function handleResultClick(rec)
  if rec and rec.variants and #rec.variants > 0 then
    DBG("result click: %s has %d variant(s)", rec.name or "<nil>", #rec.variants)
    showVariantMenu(rec)
  else
    DBG("result click: %s (no variants)", rec and rec.name or "<nil>")
    openMapForRecord(rec)
    if AM.searchBox then AM.searchBox:SetText("") end
    if AM.dropdown then AM.dropdown:Hide() end
    AM.searchBox:ClearFocus()
  end
end

local function mapLabel(rec)
  if not rec then return "" end
  local mapID = rec.mapID
  if not mapID and rec.areaName and AM.findMapIDForAreaName then
    mapID = AM.findMapIDForAreaName(rec.areaName)
    rec.mapID = mapID
  end
  if not mapID and rec.continent and rec.wx and rec.wy and AM.findMapIDForCoords then
    mapID, rec.areaName, rec.areaID = AM.findMapIDForCoords(rec.continent, rec.wx, rec.wy)
    rec.mapID = mapID
  end
  if mapID and C_Map and C_Map.GetMapInfo then
    local info = C_Map.GetMapInfo(mapID)
    if info then
      local useParent = (rec.type == "map") or (isDungeon(rec) and rec.type ~= "poi")
      if useParent and info.parentMapID and info.parentMapID > 0 then
        return AM.mapName(info.parentMapID)
      end
      return info.name
    end
  end
  if rec.areaName and rec.areaName ~= "" then return rec.areaName end
  if rec.area and rec.area ~= "" then return rec.area end
  if rec.type == "friend" or rec.type == "bnet" then return "Unknown" end
  return ""
end

local function createDropdown(parent, rowClick, showIndicator)
  rowClick = rowClick or handleResultClick
  local dd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  dd:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -4)
  dd:SetSize(parent:GetWidth(), 10)
  dd:Hide()
  dd:SetFrameStrata("DIALOG")
  dd:SetFrameLevel(parent:GetFrameLevel() + 2)
  dd.bg = dd:CreateTexture(nil, "BACKGROUND")
  dd.bg:SetAllPoints(true)
  dd.bg:SetColorTexture(0, 0, 0, 0.85)
  dd.buttons = {}
  dd.maxVisible = 10
  dd.rowHeight = 20
  dd.scroll = CreateFrame("ScrollFrame", nil, dd, "UIPanelScrollFrameTemplate")
  dd.scroll:SetPoint("TOPLEFT", 0, -2)
  dd.scroll:SetPoint("BOTTOMRIGHT", -26, 2)
  dd.content = CreateFrame("Frame", nil, dd.scroll)
  dd.content:SetSize(parent:GetWidth()-26, dd.maxVisible * dd.rowHeight)
  dd.scroll:SetScrollChild(dd.content)

  local function onClickWrapper(self)
    if rowClick then rowClick(self.__rec) end
  end

  local function makeRow(i)
    local b = CreateFrame("Button", nil, dd.content)
    b:SetPoint("TOPLEFT", 2, -(i-1)*dd.rowHeight)
    b:SetSize(dd.content:GetWidth()-4, dd.rowHeight)
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints(true)
    b.hl:SetColorTexture(1,1,1,0.08)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetJustifyH("LEFT")
    b.text2 = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.text2:SetPoint("RIGHT", -4, 0)
    b.text2:SetJustifyH("RIGHT")
    b:SetScript("OnClick", onClickWrapper)
    b:SetScript("OnKeyDown", function(self, key)
      if key == "RIGHT" then onClickWrapper(self) end
    end)
    b:EnableKeyboard(true)
    if b.SetPropagateKeyboardInput then
      b:SetPropagateKeyboardInput(true)
    end
    return b
  end

  function dd:ShowResults(list)
    DBG("dropdown: showing %d result(s)", #list)
    for _, btn in ipairs(self.buttons) do
      btn:Hide()
    end
    local limit = AM.maxResults or 25
    local total = math.min(#list, limit)
    local visible = math.min(total, self.maxVisible)
    self.content:SetHeight(total * self.rowHeight)
    self:SetHeight(visible * self.rowHeight + 6)
    self.scroll:SetVerticalScroll(0)
    self.scroll:UpdateScrollChildRect()
    if self.scroll.ScrollBar then
      self.scroll.ScrollBar:SetShown(total > visible)
    end
    self:Show()
    for i=1, total do
      local rec = list[i]
      local btn = self.buttons[i] or makeRow(i)
      self.buttons[i] = btn
      btn:Show()
      btn.__rec = rec
      local right = mapLabel(rec)
      local indicator = ""
      if showIndicator and rec.variants and #rec.variants > 0 then indicator = " [+]" end
      local leftName = rec.display or rec.name
      if isDungeon(rec) then
        btn.text:SetText((COLOR_DUNGEON.."%s"..indicator.."|r"):format(leftName))
      elseif rec.type == "poi" then
        btn.text:SetText((COLOR_POI.."%s"..indicator.."|r"):format(leftName))
      elseif rec.type == "map" then
        btn.text:SetText((COLOR_AREA.."%s"..indicator.."|r"):format(leftName))
      else
        local color = rec.connected and "|cff7cff7c" or "|cffaaaaaa"
        btn.text:SetText((color.."%s"..indicator.."|r"):format(leftName))
      end
      btn.text2:SetText(right)
    end
  end

  return dd
end

local function performSearch(q)
  q = (q or ""):gsub("^%s+","" ):gsub("%s+$","")
  local filter
  local base, filt = q:match("^(.-)%s*;%s*(%S+)%s*$")
  if filt then
    q = base
    filter = filt
  end
  if filter then
    if filter == "raid" or filter == "party" or filter == "pvp" or filter == "arena" then
      AM.variantFilter = { instance_type = filter }
    elseif filter == "current" then
      AM.variantFilter = { timeline = "current" }
    else
      AM.variantFilter = nil
    end
  else
    AM.variantFilter = nil
  end

  -- Hide any status or dropdown when there is no query
  if q == "" then
    AM.results = {}
    if AM.dropdown then AM.dropdown:Hide() end
    if AM.variantDropdown then AM.variantDropdown:Hide() end
    if AM.status then AM.status:SetText("") end
    return
  end

  local friendMode = (q:sub(1,1) == "@")
  local friendFilter = ""
  if friendMode then friendFilter = (q:sub(2) or ""):gsub("^%s+","" ):gsub("%s+$","") end
  local list
  if friendMode then
    list = searchFriends(friendFilter)
  else
    list = searchMaps(q)
  end
  AM.results = list or {}
  if AM.variantDropdown then AM.variantDropdown:Hide() end
  if #AM.results > 0 then
    AM.dropdown:ShowResults(AM.results)
    if AM.status then AM.status:SetText("") end
  else
    AM.dropdown:Hide()
    if AM.status then AM.status:SetText("|cffffaaaaNo results.|r") end
  end
end

local function resetSearch()
  AM.results = {}
  if AM.searchBox then
    AM.searchBox:SetText("")
    AM.searchBox:ClearFocus()
  end
  if AM.dropdown then AM.dropdown:Hide() end
  if AM.variantDropdown then AM.variantDropdown:Hide() end
  if AM.status then AM.status:SetText("") end
end

local function findMapFiltersButton()
  if WorldMapFrame and WorldMapFrame.overlayFrames then
    for _, f in ipairs(WorldMapFrame.overlayFrames) do
      if f.Text and f.Text.GetText and f.Text:GetText()==MAP_AND_QUEST_LOG_FILTERS then
        return f
      end
    end
  end
end

local function anchorSearchBox()
  if not AM.searchBox then return end
  local parent = WorldMapFrame and WorldMapFrame.ScrollContainer or WorldMapFrame
  if not parent then return end
  AM.searchBox:SetParent(parent)
  AM.searchBox:ClearAllPoints()
  local filters = findMapFiltersButton()
  if filters then
    AM.searchBox:SetPoint("TOPRIGHT", filters, "BOTTOMRIGHT", 160, -6)
  else
    AM.searchBox:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -44)
  end
  if AM.dropdown then
    AM.dropdown:SetParent(AM.searchBox)
  end
  if AM.variantDropdown then
    AM.variantDropdown:SetParent(AM.searchBox)
    AM.variantDropdown:ClearAllPoints()
    AM.variantDropdown:SetPoint("TOPLEFT", AM.searchBox, "TOPRIGHT", 4, -24)
  end
  if AM.statusFrame and AM.status then
    AM.statusFrame:ClearAllPoints()
    AM.statusFrame:SetPoint("TOPRIGHT", AM.searchBox, "BOTTOMRIGHT", 0, -28)
    AM.statusFrame:SetSize(300, 16)
    AM.status:ClearAllPoints()
    AM.status:SetPoint("RIGHT", AM.statusFrame, "RIGHT", 0, 0)
  end
end

local function createSearchUI()
  if not WorldMapFrame or AM.searchBox then return end
  local parent = WorldMapFrame.ScrollContainer or WorldMapFrame
  local box = CreateFrame("EditBox", "AzerothMapsSearchBox", parent, "InputBoxTemplate")
  box:SetAutoFocus(false)
  box:SetSize(300, 20)
  box:SetTextInsets(8, 8, 0, 0)
  box:SetMaxLetters(60)
  box:EnableMouse(true)
  box:SetFrameStrata("DIALOG")
  box:SetFrameLevel(WorldMapFrame:GetFrameLevel() + 100)
  local ph = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  ph:SetPoint("LEFT", box, "LEFT", 8, 0)
  ph:SetText("Search map or type '@'…")
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusGained", function() ph:Hide() end)
  box:SetScript("OnEditFocusLost", function(self) if self:GetText()=="" then ph:Show() end end)
  box:SetScript("OnTextChanged", function(self)
    local txt = self:GetText() or ""
    if txt == "" then ph:Show() else ph:Hide() end
    if not AM.suppressSearch then
      performSearch(txt)
    end
  end)
  box:SetScript("OnEnterPressed", function(self)
    if AM.results[1] then openMapForRecord(AM.results[1]) end
    self:SetText("")
    self:ClearFocus()
    AM.dropdown:Hide()
  end)
  AM.searchBox = box
  AM.dropdown = createDropdown(box, handleResultClick, true)
  AM.variantDropdown = createDropdown(box, handleVariantClick, false)
  AM.variantDropdown:ClearAllPoints()
  AM.variantDropdown:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
  local statusFrame = CreateFrame("Frame", nil, parent)
  statusFrame:SetFrameStrata("DIALOG")
  statusFrame:SetFrameLevel(box:GetFrameLevel() + 1)
  local status = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  status:SetText("")
  AM.statusFrame = statusFrame
  AM.status = status
  anchorSearchBox()
end

AM.createDropdown = createDropdown
AM.performSearch = performSearch
AM.resetSearch = resetSearch
AM.anchorSearchBox = anchorSearchBox
AM.createSearchUI = createSearchUI
AM.variantLabel = variantLabel
AM.showVariantMenu = showVariantMenu
