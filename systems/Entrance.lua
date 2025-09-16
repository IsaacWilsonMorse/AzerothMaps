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

local function findEntranceViaJournal(instanceMapID, candidates)
  if not C_EncounterJournal or not C_EncounterJournal.GetInstanceForGameMap then return nil end
  local ejID = C_EncounterJournal.GetInstanceForGameMap(instanceMapID)
  DBG("EJ lookup: %s(%d) -> ejID=%s", mapName(instanceMapID), instanceMapID, tostring(ejID))
  if not ejID then return nil end
  for _, zoneID in ipairs(candidates) do
    local entries = C_EncounterJournal.GetDungeonEntrancesForMap and C_EncounterJournal.GetDungeonEntrancesForMap(zoneID)
    if entries then
      DBG("  EJ zone %s(%d) entries=%d", mapName(zoneID), zoneID, #entries)
      for _, e in ipairs(entries) do
        if e.journalInstanceID == ejID and e.position then
          local x, y = e.position.x, e.position.y
          local info = C_Map.GetMapInfo(instanceMapID)
          local name = info and info.name or ""
          local cacheKey = tostring(instanceMapID) .. "::" .. name
          AM._entranceCache[cacheKey] = { zoneID, x, y }
          DBG("  >>> JOURNAL MATCH on %s(%d): %.3f, %.3f", mapName(zoneID), zoneID, x, y)
          return { zoneID, x, y }
        else
          if e and e.position then
            DBG("    EJ entry jid=%s pos=(%.3f,%.3f) (no match)", tostring(e.journalInstanceID), e.position.x or -1, e.position.y or -1)
          else
            DBG("    EJ entry missing position or jid (no match)")
          end
        end
      end
    end
  end
  return nil
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
  -- Generator-backed entrances (Journal), keyed by instance UiMapID
  do
    local E = _G.Entrances and _G.Entrances.recs
    if E and E[instanceMapID] and AM.WorldToMapXY then
      local rec = E[instanceMapID]
      local target = rec.map_id or rec.mapID or rec.ui
      local wx, wy = rec.wx, rec.wy
      DBG("Entrances.lua hit for %s(%d): target=%s(%s) wx=%.3f wy=%.3f", mapName(instanceMapID), instanceMapID, target and mapName(target) or "nil", tostring(target), tonumber(wx) or -1, tonumber(wy) or -1)
      if target and wx and wy then
        -- Determine continent by walking up to first Continent-type ancestor
        local cont = nil
        local cur = target
        local seen = {}
        for _=1,10 do
          if not cur or seen[cur] then break end
          seen[cur] = true
          local info = C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
          if not info then break end
          if info.mapType == Enum.UIMapType.Continent then cont = cur; break end
          cur = info.parentMapID
        end
        if cont then
          local x,y = AM.WorldToMapXY(cont, wx, wy, target)
          if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            DBG("  >>> JOURNAL DATA MATCH on %s(%d) -> %.3f, %.3f", mapName(target), target, x, y)
            AM._entranceCache[cacheKey] = { target, x, y }
            return target, x, y
          else
            DBG("  Entrances.lua projection failed for %s(%d): x=%s y=%s", mapName(target), target, tostring(x), tostring(y))
          end
        else
          DBG("  Entrances.lua: could not resolve continent for %s(%d)", mapName(target), target)
        end
      end
    elseif E and not E[instanceMapID] then
      DBG("Entrances.lua: no record for %s(%d)", instanceName or "?", instanceMapID)
    end
  end
  local candidates = getZoneAncestry(instanceMapID)
  local ej = findEntranceViaJournal(instanceMapID, candidates)
  if ej then return ej[1], ej[2], ej[3] end
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
  -- Prefer static POI dataset coordinates for exact name matches before scanning Areas
  do
    local P = _G.POIs and _G.POIs.recs
    local Areas = _G.Areas and _G.Areas.recs
    if P and AM.WorldToMapXY then
      local toks = splitTokens(instanceName or "")
      local bestTarget, bestX, bestY, bestScore
      local function edgeScore(x, y)
        local e = math.min(x, 1 - x, y, 1 - y)
        if e < 0 then e = 0 end
        return e
      end
      local ancestry = {}
      for _, z in ipairs(candidates or {}) do ancestry[z] = true end
      for _, rec in pairs(P) do
        local nm = rec and rec.name
        local nml = nm and nm:lower()
        if nml and tokensMatch(nml, toks) and rec.continent and rec.wx and rec.wy then
          -- Build target candidates: prefer POI map_id, then zone ancestors, then area chain, then coord guess
          local tryTargets, seen = {}, {}
          local function push(t)
            if t and not seen[t] then seen[t] = true; tryTargets[#tryTargets+1] = t end
          end
          -- 1) POI map_id (prefer parent if micro)
          local pmap = rec.map_id
          if pmap then
            local pinfo = C_Map.GetMapInfo and C_Map.GetMapInfo(pmap)
            if pinfo and pinfo.mapType == Enum.UIMapType.Micro and pinfo.parentMapID and pinfo.parentMapID > 0 then
              push(pinfo.parentMapID)
            end
            push(pmap)
          end
          -- 2) Zone-level ancestors of the instance map
          for _, cand in ipairs(candidates or {}) do
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(cand)
            if info and info.mapType == Enum.UIMapType.Zone then push(cand) end
          end
          -- 3) Area chain for this POI's area (zone-only)
          local aid = rec.area
          local guard, cur = 0, (Areas and aid and Areas[aid]) or nil
          while cur and guard < 10 do
            guard = guard + 1
            local mid = cur.map_id or cur.mapID
            if mid then
              local info = C_Map.GetMapInfo and C_Map.GetMapInfo(mid)
              if info and info.mapType == Enum.UIMapType.Zone then push(mid) end
            end
            local pid = cur.parent_map_id or (cur.parent and Areas[cur.parent] and Areas[cur.parent].map_id)
            if pid and Areas then
              local nextAr
              for _, a in pairs(Areas) do if a and (a.map_id == pid or a.mapID == pid) then nextAr = a; break end end
              cur = nextAr
            else
              cur = nil
            end
          end
          -- 4) Coord-based guess
          if AM.findMapIDForCoords then
            local guess = AM.findMapIDForCoords(rec.continent, rec.wx, rec.wy)
            push(guess)
          end
          -- Log candidate list for debugging
          do
            local labels = {}
            for _, t in ipairs(tryTargets) do labels[#labels+1] = string.format("%s(%d)", mapName(t), t) end
            if #labels > 0 then DBG("    POI candidate targets: %s", table.concat(labels, ", ")) end
          end
          -- Try conversion on each target, with scoring
          for _, target in ipairs(tryTargets) do
            local info = C_Map.GetMapInfo and C_Map.GetMapInfo(target)
            local attempts = {
              { rec.wx, rec.wy },
            }
            local ar = (Areas and aid and Areas[aid]) or nil
            if ar and ar.wx and ar.wy then attempts[#attempts+1] = { ar.wx, ar.wy } end
            for _, pair in ipairs(attempts) do
              local x, y = AM.WorldToMapXY(rec.continent, pair[1], pair[2], target)
              if x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
                -- Filter out suspicious center projections (0.5, 0.5) which can occur when the API fails
                local isCenter = math.abs(x - 0.5) < 0.02 and math.abs(y - 0.5) < 0.02
                if isCenter then
                  DBG("    SKIP center projection for %s(%d): x=%.3f y=%.3f", mapName(target), target, x, y)
                else
                  local score = 0
                  -- Prefer zones strongly
                  if info and info.mapType == Enum.UIMapType.Zone then score = score + 100 end
                  -- Prefer targets in the instance ancestry
                  if ancestry[target] then score = score + 10 end
                  -- Prefer the POI-declared map
                  if pmap and target == pmap then score = score + 20 end
                  -- Prefer pins away from the edge
                  score = score + edgeScore(x, y) * 10
                  local src = (pair[1] == rec.wx and pair[2] == rec.wy) and "POI" or "AREA"
                  DBG("    SCORE %s(%d) src=%s -> x=%.3f y=%.3f score=%.3f", mapName(target), target, src, x, y, score)
                  if not bestScore or score > bestScore then
                    bestScore, bestTarget, bestX, bestY = score, target, x, y
                  end
                end
              else
                local src = (pair[1] == rec.wx and pair[2] == rec.wy) and "POI" or "AREA"
                DBG("    Projection failed for %s(%d) src=%s", mapName(target), target, src)
              end
            end
          end
        end
      end
      if bestTarget and bestX and bestY then
        DBG("  >>> POI DATA MATCH on %s(%d) -> %.3f, %.3f", mapName(bestTarget), bestTarget, bestX, bestY)
        AM._entranceCache[cacheKey] = { bestTarget, bestX, bestY }
        return bestTarget, bestX, bestY
      end
    end
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
      -- Two-pass scan: prefer dungeon-type areas when available, then any area.
      local function areaPass(preferDungeon)
        for _, rec in pairs(Areas) do
          if rec and rec.continent and rec.parent_map_id and rec.wx and rec.wy and
             (inCandidates(rec.map_id or rec.mapID) or inCandidates(rec.parent_map_id) or rec.continent == instanceMapID) then
            local nm = (rec.name or rec.zone or ""):lower()
          local isDungeonType = (rec.type == "dungeon") or (rec.type_id and tonumber(rec.type_id) and tonumber(rec.type_id) >= 4)
          if tokensMatch(nm, tokens) and ((preferDungeon and isDungeonType) or (not preferDungeon)) then
              DBG("    Considering Areas rec %s: map=%s parent=%s continent=%s", rec.name or rec.zone or "?", tostring(rec.map_id or rec.mapID), tostring(rec.parent_map_id), tostring(rec.continent))
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
        return nil, nil, nil
      end
      -- Try dungeon areas first, then any matching area.
      local p, ax, ay = areaPass(true)
      if p and ax and ay then return p, ax, ay end
      return areaPass(false)
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
