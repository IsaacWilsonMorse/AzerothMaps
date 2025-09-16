-- Addon bootstrap and event dispatch.
local AZEROTH_MAPS, NS = ...
local AM = NS
_G.AzerothMaps = AM

AM.debug = false
AM.autoSupertrack = true
AM.autoNavigate = false
AM.flashWorldMapPin = true
AM.maxResults = 25
AM.preferInstanceMap = false
AM.results = {}
AM.friendsLoaded = false
AM_DebugLog = {}

-- Discover addon version from metadata
local function _GetAddonVersion()
  local v
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    v = C_AddOns.GetAddOnMetadata(AZEROTH_MAPS, "Version")
  elseif GetAddOnMetadata then
    v = GetAddOnMetadata(AZEROTH_MAPS, "Version")
  end
  if not v or v == "" then v = "unknown" end
  return v
end
AM.version = _GetAddonVersion()

local function DBG(fmt, ...)
  if not AM.debug then return end
  local msg = string.format(fmt, ...)
  local out = "|cff33ff99AzerothMaps-D|r: " .. msg

  -- Print to chat
  print(out)

  -- Append to log table (time-stamped)
  table.insert(_G.AM_DebugLog["Logs"], string.format("[%s] %s", date("%H:%M:%S"), msg))
end
AM.DBG = DBG

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("FRIENDLIST_UPDATE")
ev:RegisterEvent("BN_FRIEND_INFO_CHANGED")
ev:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
ev:RegisterEvent("BN_FRIEND_ACCOUNT_OFFLINE")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if AM.createSearchUI then AM.createSearchUI() end
    if AM.rebuildFriendIndex then AM.rebuildFriendIndex() end
    if WorldMapFrame then
      WorldMapFrame:HookScript("OnShow", AM.anchorSearchBox)
      WorldMapFrame:HookScript("OnSizeChanged", AM.anchorSearchBox)
      WorldMapFrame:HookScript("OnHide", AM.resetSearch)
    end
  elseif event == "FRIENDLIST_UPDATE" then
    AM.friendsLoaded = true
    if AM.rebuildFriendIndex then AM.rebuildFriendIndex(true) end
    if AM.searchBox and AM.searchBox:GetText() ~= "" and AM.performSearch then
      AM.performSearch(AM.searchBox:GetText())
    end
    if AM.anchorSearchBox then AM.anchorSearchBox() end
  else
    if AM.friendsLoaded and AM.rebuildFriendIndex then AM.rebuildFriendIndex() end
    if AM.friendsLoaded and AM.searchBox and AM.searchBox:GetText() ~= "" and AM.performSearch then
      AM.performSearch(AM.searchBox:GetText())
    end
    if AM.anchorSearchBox then AM.anchorSearchBox() end
  end
end)

return AM, DBG
