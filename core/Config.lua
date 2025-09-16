-- SavedVariables backing store and options panel.
local AZEROTH_MAPS, AM = ...

-- Simple SavedVariables backing store
local DEFAULTS = {
  debug = false,
  autoSupertrack = true,
  autoNavigate = false,
  flashWorldMapPin = true,
  maxResults = 25,
  preferInstanceMap = false,
  useTomTom = true,
  filterPOIs = true,
  filterAreas = true,
  enableReportButton = false,
  reports = {},
}

local function copyDefaults(dst, src)
  if type(dst) ~= "table" then dst = {} end
  for k, v in pairs(src) do if dst[k] == nil then dst[k] = v end end
  return dst
end

-- Apply DB values into runtime flags
function AM.ApplyConfig()
  _G.AM_DebugLog["Logs"] = {}
  -- Ensure persistent reports storage exists (do not wipe across restarts)
  local db = _G.AzerothMapsDB or {}
  if type(db.reports) ~= "table" then db.reports = {} end
  _G.AzerothMapsDB = db
  local db = _G.AzerothMapsDB or {}
  AM.debug = not not db.debug
  AM.autoSupertrack = not not db.autoSupertrack
  AM.autoNavigate = not not db.autoNavigate
  AM.flashWorldMapPin = not not db.flashWorldMapPin
  AM.maxResults = (type(db.maxResults) == "number" and db.maxResults > 0) and math.floor(db.maxResults) or DEFAULTS.maxResults
  local oldPref = AM.preferInstanceMap
  AM.preferInstanceMap = not not db.preferInstanceMap
  if oldPref ~= AM.preferInstanceMap then
    AM._poiList = nil
    AM._poiByName = nil
    AM._poiDuplicates = nil
    AM.mapIndex = nil
    AM._mapsScanned = nil
    AM._dungeonsAdded = nil
    AM._areasAdded = nil
  end
  AM.useTomTom = not not db.useTomTom
  local oldArea = AM.filterAreas
  AM.filterAreas = db.filterAreas ~= false
  if oldArea ~= AM.filterAreas then
    AM._poiList = nil
    AM._poiByName = nil
    AM._poiDuplicates = nil
    AM.mapIndex = nil
    AM._mapsScanned = nil
    AM._dungeonsAdded = nil
    AM._areasAdded = nil
  end
  local oldFilter = AM.filterPOIs
  AM.filterPOIs = db.filterPOIs ~= false
  if oldFilter ~= AM.filterPOIs then
    AM._poiList = nil
    AM._poiByName = nil
    AM._poiDuplicates = nil
    AM.mapIndex = nil
    AM._mapsScanned = nil
    AM._dungeonsAdded = nil
    AM._areasAdded = nil
  end
  AM.enableReportButton = db.enableReportButton and true or false
  if AM.searchBox and AM.reportButton then
    if AM.enableReportButton then AM.reportButton:Show() else AM.reportButton:Hide() end
  end
end

-- Options panel (works in both new and legacy Settings UIs)
local panel
local function newCheckbox(parent, label, tooltip, dbKey)
  local cb = CreateFrame("CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
  cb.Text:SetText(label)
  if tooltip and cb then cb.tooltipText = label; cb.tooltipRequirement = tooltip end
  cb:SetScript("OnClick", function(self)
    _G.AzerothMapsDB[dbKey] = self:GetChecked() and true or false
    AM.ApplyConfig()
  end)
  cb.dbKey = dbKey
  return cb
end

local function refreshPanel()
  if not panel or not _G.AzerothMapsDB then return end
  for _, child in ipairs({panel:GetChildren()}) do
    if child.dbKey then
      local key = child.dbKey
      local val = _G.AzerothMapsDB[key]
      local objType = child.GetObjectType and child:GetObjectType()

      if objType == "CheckButton" and child.SetChecked then
        child:SetChecked(val and true or false)

      elseif objType == "EditBox" and child.SetText then
        local fallback = DEFAULTS[key]
        if type(val) == "number" then
          child:SetText(tostring(val))
        elseif fallback ~= nil then
          child:SetText(tostring(fallback))
        else
          child:SetText("")
        end
      end
    end
  end
end

function AM.CreateOptionsPanel()
  if panel then return panel end
  panel = CreateFrame("Frame")
  panel.name = "AzerothMaps"
  panel:Hide()

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("AzerothMaps - Options")

  local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  sub:SetText("Configure search, navigation and debug settings.")

  local y = -48
  local function addCB(text, tip, key)
    local cb = newCheckbox(panel, text, tip, key)
    cb:SetPoint("TOPLEFT", 16, y)
    y = y - 28
    return cb
  end
  
  local function addEditBox(label, tip, key)
    local lbl = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", 16, y - 4)
    lbl:SetText(label)
    local eb = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    eb:SetSize(50, 20)
    eb:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(3)
    eb:SetJustifyH("LEFT")
    if tip and eb then eb.tooltipText = label; eb.tooltipRequirement = tip end
    eb:SetScript("OnEnterPressed", function(self)
      local v = tonumber(self:GetText())
      if v and v > 0 then
        v = math.floor(v)
        _G.AzerothMapsDB[key] = v
        AM.ApplyConfig()
        self:SetText(tostring(_G.AzerothMapsDB[key] or DEFAULTS[key]))
      else
        self:SetText(tostring(_G.AzerothMapsDB[key] or DEFAULTS[key]))
      end
      self:ClearFocus()
    end)
    eb:SetScript("OnEscapePressed", function(self)
      self:SetText(tostring(_G.AzerothMapsDB[key] or DEFAULTS[key]))
      self:ClearFocus()
    end)
    eb.dbKey = key
    eb:SetText(tostring((_G.AzerothMapsDB and _G.AzerothMapsDB[key]) or DEFAULTS[key] or ""))
    y = y - 28
    return eb
  end


  addCB("Enable debug logging", "Print additional debug info to chat.", "debug")
  addCB("Enable Blizzard navigator", "Supertrack the last waypoint automatically.", "autoSupertrack")
  addCB("Use TomTom if available", "Set TomTom waypoints and arrow when navigating.", "useTomTom")
  addCB("Auto-navigate", "Pathfind and set waypoints when selecting a result.", "autoNavigate")
  addCB("Prefer instance map", "Use in-instance coordinates when available. Disable to favor dungeon entrances.", "preferInstanceMap")
  addCB("Filter areas", "Hide unused, arena and PvP areas and dungeons.", "filterAreas")
  addCB("Filter POIs", "Hide portal, zeppelin, PvP and unused POIs.", "filterPOIs")
  addCB("Center World Map on waypoint", "Zoom and center on the waypoint when placing it.", "flashWorldMapPin")
  addEditBox("Max search results", "Maximum number of search results to show (1-100).", "maxResults")
  addCB("Show 'Report Broken' button", "Enable a button next to the search bar to report the last selected result as broken.", "enableReportButton")

  panel:SetScript("OnShow", refreshPanel)

  -- Register with both Settings (DF+) and legacy Interface Options
  if Settings and Settings.RegisterAddOnCategory and Settings.RegisterCanvasLayoutCategory then
    local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    AM._settingsCategory = cat
    Settings.RegisterAddOnCategory(cat)
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end

  return panel
end

function AM.OpenConfig()
  AM.CreateOptionsPanel()
  if Settings and Settings.OpenToCategory and AM._settingsCategory then
    Settings.OpenToCategory(AM._settingsCategory)
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(panel)
    InterfaceOptionsFrame_OpenToCategory(panel)
  end
end

-- SavedVariables bootstrapping
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == AZEROTH_MAPS then
    _G.AzerothMapsDB = copyDefaults(_G.AzerothMapsDB, DEFAULTS)
    AM.ApplyConfig()
  elseif event == "PLAYER_LOGIN" then
    AM.CreateOptionsPanel()
  end
end)

