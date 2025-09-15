-- Maintain an index of online friends and Battle.net contacts.
local AZEROTH_MAPS, AM = ...
local DBG = AM.DBG

AM.friendIndex = AM.friendIndex or {}

local function rebuildFriendIndex(skipRequest)
  if not skipRequest and C_FriendList and C_FriendList.ShowFriends then
    C_FriendList.ShowFriends()
  end
  local num = C_FriendList.GetNumFriends and C_FriendList.GetNumFriends() or 0
  local bnNum = BNGetNumFriends and BNGetNumFriends() or 0
  if num == 0 and bnNum == 0 and not AM.friendsLoaded then
    return
  end
  wipe(AM.friendIndex)
  for i = 1, num do
    local info = C_FriendList.GetFriendInfoByIndex(i)
    if info then
      table.insert(AM.friendIndex, {
        type = "friend",
        name = info.name,
        area = info.area,
        guid = info.guid,
        className = info.className,
        level = info.level,
        connected = info.connected,
      })
    end
  end

  for i = 1, bnNum do
    local accInfo = C_BattleNet and C_BattleNet.GetFriendAccountInfo and C_BattleNet.GetFriendAccountInfo(i)
    if accInfo then
      local gameInfo = accInfo.gameAccountInfo
      local name
      if gameInfo and gameInfo.characterName and gameInfo.characterName ~= "" then
        name = gameInfo.characterName
        if gameInfo.realmName and gameInfo.realmName ~= "" then
          name = name .. "-" .. gameInfo.realmName
        end
      else
        name = accInfo.accountName or accInfo.battleTag
      end
      table.insert(AM.friendIndex, {
        type = "bnet",
        name = name,
        area = gameInfo and gameInfo.areaName,
        guid = gameInfo and gameInfo.playerGuid,
        className = gameInfo and gameInfo.className,
        level = gameInfo and gameInfo.characterLevel,
        connected = (gameInfo and gameInfo.isOnline) or accInfo.isOnline or false,
      })
    end
  end
end

local function friendUnitTokenByName(name)
  DBG("friendUnitTokenByName: searching for "..tostring(name))
  if UnitInRaid("player") then
    DBG("friendUnitTokenByName: in raid, searching raid units")
    for i=1,40 do
      local u = "raid"..i
      if UnitExists(u) then
        local n = GetUnitName(u, true)
        if n and n:lower():find(name:lower(), 1, true) then
          return u
        end
      end
    end
  else
    DBG("friendUnitTokenByName: not in raid, searching party units")
    for i=1,4 do
      local u = "party"..i
      DBG("friendUnitTokenByName: checking unit "..u)
      if UnitExists(u) then
        DBG("friendUnitTokenByName: checking unit "..u)
        local n = GetUnitName(u, true)
        if n and n:lower():find(name:lower(), 1, true) then
          return u
        end
      end
    end
  end
  return nil
end

local function searchFriends(filter)
  local f = (filter or ""):lower()
  local out = {}
  for _, rec in ipairs(AM.friendIndex) do
    if f == "" or rec.name:lower():find(f, 1, true) then
      table.insert(out, rec)
    end
  end
  table.sort(out, function(a, b)
    if a.connected ~= b.connected then return a.connected end
    return a.name < b.name
  end)
  DBG("searchFriends(%q) -> %d result(s)", f, #out)
  return out
end

AM.rebuildFriendIndex = rebuildFriendIndex
AM.friendUnitTokenByName = friendUnitTokenByName
AM.searchFriends = searchFriends
