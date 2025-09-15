-- Locate probable entrance points for instance maps.
local AZEROTH_MAPS, AM = ...
local DBG = AM.DBG
local mapName = AM.mapName

AM._entranceCache = AM._entranceCache or {}
AM.entranceOverrides = AM.entranceOverrides or {}

local function collectLinksForMap(mapID)
  local out = {}
  local links = C_Map.GetMapLinksForMap and C_Map.GetMapLinksForMap(mapID)
  if not links then return out end
  DBG("  collectLinks: %s(%d) -> %d link(s)", mapName(mapID), mapID, #links)
  for i, link in ipairs(links) do
    local name = link.name or ""
    local pos = link.position
    local x, y = pos and pos.x or nil, pos and pos.y or nil
    out[#out+1] = {
      kind = "link",
      name = name,
      x = x, y = y,
      link = link,
    }
    if i <= 12 then
      DBG("    LINK %d: %s (%.3f, %.3f) -> %s", i, name, x or -1, y or -1, tostring(link.linkedUiMapID or link.uiMapID or "?"))
    end
  end
  return out
end

local function splitTokens(s)
  local t = {}
  for w in tostring(s):gmatch("%w+") do t[#t+1] = w:lower() end
  return t
end

local function tokensMatch(nameLower, tokens)
  if #tokens == 0 then return false end
  local hits = 0
  for _, tok in ipairs(tokens) do
    if nameLower:find(tok, 1, true) then hits = hits + 1 end
  end
  return hits >= math.max(1, math.ceil(#tokens * 0.6))
end

local KEY_WORDS = { "entrance", "portal", "delve", "dungeon", "instance" }

local function containsKeyword(nameLower)
  for _, k in ipairs(KEY_WORDS) do
    if nameLower:find(k, 1, true) then return true end
  end
  return false
end

local function getZoneAncestry(mapID)
  local out, seen = {}, {}
  local id = mapID
  for _=1,10 do
    local info = id and C_Map.GetMapInfo(id)
    if not info or seen[id] then break end
    seen[id] = true
    if info.mapType == Enum.UIMapType.Zone or info.mapType == Enum.UIMapType.Continent then
      out[#out+1] = id
    end
    id = info.parentMapID
  end
  local here = C_Map.GetBestMapForUnit("player")
  if here then table.insert(out, 1, here) end
  local names = {}
  for _, mid in ipairs(out) do names[#names+1] = string.format("%s(%d)", mapName(mid), mid) end
  DBG("Ancestry for %s(%d): %s", mapName(mapID), mapID, table.concat(names, " -> "))
  return out
end

local function collectPOIsForMap(mapID)
  local out = {}
  local ids = C_AreaPoiInfo and C_AreaPoiInfo.GetAreaPOIForMap and C_AreaPoiInfo.GetAreaPOIForMap(mapID)
  if ids then
    for _, id in ipairs(ids) do
      local poi = C_AreaPoiInfo.GetAreaPOIInfo(mapID, id)
      if poi and poi.name and poi.position then
        out[#out+1] = { kind="area", id=id, name=poi.name, x=poi.position.x, y=poi.position.y }
      end
    end
  end
  local m = C_Map.GetMapPointsOfInterest and C_Map.GetMapPointsOfInterest(mapID)
  if m then
    for _, poi in ipairs(m) do
      if poi.name and poi.position then
        out[#out+1] = {
          kind="map",
          id=poi.poiID or 0,
          name=poi.name,
          x=poi.position.x, y=poi.position.y,
          atlas=poi.atlasName
        }
      end
    end
  end
  DBG("  collectPOIs: %s(%d) -> %d POIs", mapName(mapID), mapID, #out)
  return out
end

local function findEntranceForInstance(instanceMapID, instanceName)
  local ov = AM.entranceOverrides[instanceMapID]
  if ov then
    DBG("Entrance override hit for %s(%d): parent=%s(%d) x=%.3f y=%.3f", instanceName or "?", instanceMapID, mapName(ov[1]), ov[1], ov[2], ov[3])
    return ov[1], ov[2], ov[3]
  end
  local cacheKey = tostring(instanceMapID) .. "::" .. (instanceName or "")
  if AM._entranceCache[cacheKey] then
    local p,x,y = unpack(AM._entranceCache[cacheKey])
    DBG("Entrance cache hit for %s(%d): parent=%s(%s) x=%.3f y=%.3f", instanceName or "?", instanceMapID, p and mapName(p) or "nil", tostring(p), x or -1, y or -1)
    return p,x,y
  end
  local tokens = splitTokens(instanceName or "")
  local candidates = getZoneAncestry(instanceMapID)
  DBG("Finding entrance for %s(%d). Candidates=%d", instanceName or "?", instanceMapID, #candidates)
  local function atlasLooksEntrance(atlas)
    if not atlas then return false end
    atlas = atlas:lower()
    return atlas:find("dungeon") or atlas:find("portal") or atlas:find("delve") or atlas:find("cave") or atlas:find("entrance")
  end
  for _, parent in ipairs(candidates) do
    if C_Map.RequestPreloadMap then C_Map.RequestPreloadMap(parent) end
    local pois = collectPOIsForMap(parent)
    local logged = 0
    for _, p in ipairs(pois) do
      local n = (p.name or ""):lower()
      if logged < 12 then
        DBG("    %sPOI %d: %s (%.3f, %.3f) %s", p.kind=="map" and "Map" or "Area", p.id or 0, p.name or "?", p.x or -1, p.y or -1, p.atlas and ("atlas="..p.atlas) or "")
        logged = logged + 1
      end
      if (tokensMatch(n, tokens) or (containsKeyword(n) and tokensMatch(n, tokens)) or atlasLooksEntrance(p.atlas)) and p.x and p.y then
        DBG("  >>> MATCH on %s(%d): %s (x=%.3f y=%.3f)", mapName(parent), parent, p.name or "?", p.x, p.y)
        AM._entranceCache[cacheKey] = { parent, p.x, p.y }
        return parent, p.x, p.y
      end
    end
    local links = collectLinksForMap(parent)
    for _, L in ipairs(links) do
      local n = (L.name or ""):lower()
      local linked = L.link and (L.link.linkedUiMapID or L.link.uiMapID)
      if ((linked == instanceMapID) or tokensMatch(n, tokens) or containsKeyword(n)) and L.x and L.y then
        DBG("  >>> LINK MATCH on %s(%d): %s (x=%.3f y=%.3f) -> %s", mapName(parent), parent, L.name or "?", L.x, L.y, tostring(linked))
        AM._entranceCache[cacheKey] = { parent, L.x, L.y }
        return parent, L.x, L.y
      end
    end
  end
  local parent, ex, ey = AM._am_findOfflineEntrance(instanceMapID, instanceName, candidates)
  if parent and ex and ey then
    DBG("  >>> OFFLINE FALLBACK MATCH on %s(%d) -> %.3f, %.3f", mapName(parent), parent, ex, ey)
    AM._entranceCache[cacheKey] = { parent, ex, ey }
    return parent, ex, ey
  end
  -- Fallback to static area metadata when dynamic and offline lookups fail.
  local Areas = _G.Areas and _G.Areas.recs
  if Areas then
    local count = 0
    for _ in pairs(Areas) do count = count + 1 end
    DBG("  Scanning Areas fallback (%d record(s))", count)
    if not AM.WorldToMapXY then
      DBG("  Areas fallback skipped: WorldToMapXY unavailable")
    else
      local function inCandidates(id)
        if not id then return false end
        if id == instanceMapID then return true end
        for _, c in ipairs(candidates) do if c == id then return true end end
        return false
      end
      for _, rec in pairs(Areas) do
        if rec and rec.continent and rec.parent_map_id and rec.wx and rec.wy and
           (inCandidates(rec.map_id) or inCandidates(rec.parent_map_id) or rec.continent == instanceMapID) then
          local nm = (rec.name or rec.zone or ""):lower()
          if tokensMatch(nm, tokens) then
            DBG("    Considering Areas rec %s: map=%s parent=%s continent=%s", rec.name or rec.zone or "?", tostring(rec.map_id), tostring(rec.parent_map_id), tostring(rec.continent))
            local x, y
            local tried = {}
            local function attempt(continent)
              if not continent or tried[continent] then return nil, nil end
              tried[continent] = true
              local ax, ay = AM.WorldToMapXY(continent, rec.wx, rec.wy, rec.parent_map_id)
              if ax and ay and ax >= 0 and ax <= 1 and ay >= 0 and ay <= 1 then
                DBG("    WorldToMapXY succeeded using %s(%d)", mapName(continent), continent)
                return ax, ay
              else
                DBG("    WorldToMapXY failed using %s(%d)", mapName(continent), continent)
                return nil, nil
              end
            end
            -- first try the continent specified on the record
            x, y = attempt(rec.continent)
            -- if that fails, try ancestors of the instance map
            if not x or not y then
              for _, alt in ipairs(candidates) do
                x, y = attempt(alt)
                if x and y then break end
              end
            end
            if x and y then
              DBG("  >>> AREAS FALLBACK MATCH on %s(%d) -> %.3f, %.3f", mapName(rec.parent_map_id), rec.parent_map_id, x, y)
              AM._entranceCache[cacheKey] = { rec.parent_map_id, x, y }
              return rec.parent_map_id, x, y
            end
          end
        end
      end
    end
  else
    DBG("  Areas dataset unavailable for fallback")
  end
  DBG("  No entrance POI found for %s(%d)", instanceName or "?", instanceMapID)
  AM._entranceCache[cacheKey] = { nil, nil, nil }
  return nil, nil, nil
end

local function isInstanceLike(mapID)
  local info = mapID and C_Map.GetMapInfo(mapID)
  if not info then return false end
  return info.mapType == Enum.UIMapType.Dungeon or info.mapType == Enum.UIMapType.Micro
end

AM.collectPOIsForMap = collectPOIsForMap
AM.collectLinksForMap = collectLinksForMap
AM.getZoneAncestry = getZoneAncestry
AM.findEntranceForInstance = findEntranceForInstance
AM.isInstanceLike = isInstanceLike
