-- Build a searchable index of maps and their variants.
local AZEROTH_MAPS, AM = ...
local DBG = AM.DBG

local _preloaded = {}
local allowedTypes = {
  [Enum.UIMapType.Continent] = true,
  [Enum.UIMapType.Zone]      = true,
  [Enum.UIMapType.Micro]     = true,
  [Enum.UIMapType.Dungeon]   = true,
}

local Expansions = _G.Expansions and _G.Expansions.recs or {}
local EXPANSION_BY_ROOT = {}
for id, rec in pairs(Expansions) do
  if type(rec) == "table" then
    EXPANSION_BY_ROOT[id] = rec.expansion_id or rec[1]
  else
    EXPANSION_BY_ROOT[id] = rec
  end
end

local function rootMap(id)
  local seen = {}
  while id and id > 0 and not seen[id] do
    seen[id] = true
    local info = C_Map.GetMapInfo(id)
    if not (info and info.parentMapID and info.parentMapID > 0) then
      break
    end
    id = info.parentMapID
  end
  return id
end

local function expansionForMap(id)
  local root = rootMap(id)
  return root and EXPANSION_BY_ROOT[root]
end

local function mapName(id)
  local info = id and C_Map.GetMapInfo(id)
  return info and info.name or ("<map "..tostring(id)..">")
end

local function preload(mapID)
  if not mapID or _preloaded[mapID] then return end
  if C_Map and C_Map.RequestPreloadMap then
    C_Map.RequestPreloadMap(mapID)
    _preloaded[mapID] = true
    DBG("Preload requested for %s(%d)", mapName(mapID), mapID)
  end
end

local function buildMapIndex()
  AM.mapIndex = AM.mapIndex or {}
  -- 1) Build from live C_Map so we pick up everything available in the client.
  if not AM._mapsScanned then
    local ids = C_Map.GetMapIDs and C_Map.GetMapIDs()
    if type(ids) == "table" then
      for _, id in ipairs(ids) do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and allowedTypes[info.mapType] then
          local key = info.name:lower()
          local existing = AM.mapIndex[key]
          local exp = expansionForMap(id)
          if existing then
            existing.variants = existing.variants or {}
            table.insert(existing.variants, { mapID = id, name = info.name, type = "map", expansion_id = exp })
          else
            AM.mapIndex[key] = { mapID = id, name = info.name, type = "map", expansion_id = exp }
          end
        end
      end
    else
      local id = 1
      while true do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if info.name and allowedTypes[info.mapType] then
          local key = info.name:lower()
          local existing = AM.mapIndex[key]
          local exp = expansionForMap(id)
          if existing then
            existing.variants = existing.variants or {}
            table.insert(existing.variants, { mapID = id, name = info.name, type = "map", expansion_id = exp })
          else
            AM.mapIndex[key] = { mapID = id, name = info.name, type = "map", expansion_id = exp }
          end
        end
        id = id + 1
      end
    end
    AM._mapsScanned = true
  end
  -- 2) Augment with offline dungeons metadata, if present.
  local D = _G.Dungeons and _G.Dungeons.recs
  if D and not AM._dungeonsAdded then
    local added = 0
    for id, rec in pairs(D) do
      local name = rec and rec.name
      if name and type(name) == "string" then
        local key = name:lower()
        local existing = AM.mapIndex[key]
        if existing then
          existing.variants = existing.variants or {}
          local dup = {}
          for k,v in pairs(rec) do dup[k]=v end
          dup.mapID = id
          dup.name = name
          dup.expansion_id = dup.expansion_id or expansionForMap(id)
          table.insert(existing.variants, dup)
        else
          local newRec = {}
          for k,v in pairs(rec) do newRec[k]=v end
          newRec.mapID = id
          newRec.name = name
          newRec.type = "map"
          newRec.expansion_id = newRec.expansion_id or expansionForMap(id)
          AM.mapIndex[key] = newRec
          added = added + 1
        end
      end
    end
    if added > 0 then DBG("Augmented map index with %d dungeon name(s)", added) end
    AM._dungeonsAdded = true
  end
  -- 3) Add area aliases from Areas.lua when a UiMapID is known
  local A = _G.Areas and _G.Areas.recs
  if A and not AM._areasAdded then
    local added = 0
    for aid, rec in pairs(A) do
      local nm = rec and rec.name
      local mid = rec and (rec.map_id or rec.mapID)
      if nm and mid and type(nm) == "string" and type(mid) == "number" then
        local key = nm:lower()
        local x, y
        if rec.continent and rec.wx and rec.wy and AM.WorldToMapXY then
          x, y = AM.WorldToMapXY(rec.continent, rec.wx, rec.wy, mid)
        end
        local existing = AM.mapIndex[key]
        if existing then
          existing.variants = existing.variants or {}
          table.insert(existing.variants, { mapID = mid, name = nm, type = "map", x = x, y = y, areaID = aid, expansion_id = rec.expansion_id, timeline = rec.timeline, phase_id = rec.phase_id, phase_group = rec.phase_group })
        else
          AM.mapIndex[key] = { mapID = mid, name = nm, type = "map", x = x, y = y, areaID = aid, expansion_id = rec.expansion_id, timeline = rec.timeline, phase_id = rec.phase_id, phase_group = rec.phase_group }
          added = added + 1
        end
      end
    end
    if added > 0 then DBG("Augmented map index with %d area name(s)", added) end
    AM._areasAdded = true
  end
  DBG("Built map index with %d names", (function() local c=0 for _ in pairs(AM.mapIndex) do c=c+1 end return c end)())
end

local function buildPoiIndex()
  if AM._poiList then return end
  local P = _G.POIs and _G.POIs.recs
  if not P then return end
  local A = _G.Areas and _G.Areas.recs or {}
  AM.buildMapIndex()
  AM._poiList = {}
  AM._poiByName = {}
  local count = 0
  for id, rec in pairs(P) do
    local name = rec and rec.name
    if name and type(name) == "string" and name ~= "" then
      local nml = name:lower()
      local mapDup = AM.mapIndex and AM.mapIndex[nml]
      if mapDup then
        -- record duplicate POI names without removing existing map entries
        AM._poiDuplicates = AM._poiDuplicates or {}
        AM._poiDuplicates[nml] = true
      end
      local areaName
      if rec.area and A[rec.area] and A[rec.area].name then
        areaName = A[rec.area].name
      end
      local mapID = rec.map_id or rec.mapID
      local x, y
      if rec.continent and rec.wx and rec.wy and mapID and AM.WorldToMapXY then
        x, y = AM.WorldToMapXY(rec.continent, rec.wx, rec.wy, mapID)
      end
      if mapID and not mapDup then
        local info = C_Map.GetMapInfo(mapID)
        if info and info.name then
          AM.mapIndex[info.name:lower()] = { mapID = mapID, name = info.name, type = "map", expansion_id = rec.expansion_id, timeline = rec.timeline, phase_id = rec.phase_id, phase_group = rec.phase_group }
          mapDup = AM.mapIndex[info.name:lower()]
        end
      end
      local poi = {
        type = "poi",
        poiID = id,
        name = name,
        name_l = nml,
        areaID = rec.area,
        areaName = areaName,
        continent = rec.continent,
        mapID = mapID,
        x = x,
        y = y,
        wx = rec.wx,
        wy = rec.wy,
        expansion_id = rec.expansion_id,
        timeline = rec.timeline,
        phase_id = rec.phase_id,
        phase_group = rec.phase_group,
        -- mapID/x/y resolved lazily when opening the record
      }
      table.insert(AM._poiList, poi)
      AM._poiByName[nml] = AM._poiByName[nml] or {}
      table.insert(AM._poiByName[nml], poi)
      if mapDup or #AM._poiByName[nml] > 1 then
        AM._poiDuplicates = AM._poiDuplicates or {}
        AM._poiDuplicates[nml] = true
      end
      count = count + 1
    end
  end
  DBG("Built POI index with %d entries", count)
end

local function findMapIDForAreaName(area)
  AM.buildMapIndex()
  if not area or area == "" then return nil end
  local function isValid(id)
    return id and (not C_Map or not C_Map.GetMapInfo or C_Map.GetMapInfo(id) ~= nil)
  end
  local function pickMapID(rec)
    if not rec then return nil end
    if isValid(rec.mapID) then return rec.mapID end
    if rec.variants then
      for _, v in ipairs(rec.variants) do
        if isValid(v.mapID) then return v.mapID end
      end
    end
    return rec.mapID
  end
  local key = area:lower()
  local rec = AM.mapIndex and AM.mapIndex[key]
  local mid = pickMapID(rec)
  if mid then return mid end
  -- fallback: partial match
  for name, rec in pairs(AM.mapIndex or {}) do
    if name:find(key, 1, true) then
      return pickMapID(rec)
    end
  end
  return nil
end

-- Attempt to guess a mapID from world coordinates.
-- Looks for the closest Area entry on the same continent and returns
-- its map_id along with the area's name and ID.
local function findMapIDForCoords(continent, wx, wy)
  local Areas = _G.Areas and _G.Areas.recs
  if not (Areas and continent and wx and wy) then return nil end
  local bestDistSq, bestMapID, bestName, bestAID
  for aid, ar in pairs(Areas) do
    if ar.continent == continent and ar.map_id and ar.wx and ar.wy then
      local dx, dy = ar.wx - wx, ar.wy - wy
      local d2 = dx*dx + dy*dy
      if not bestDistSq or d2 < bestDistSq then
        bestDistSq, bestMapID, bestName, bestAID = d2, ar.map_id, ar.name, aid
      end
    end
  end
  return bestMapID, bestName, bestAID
end

local function searchMaps(q)
  AM.buildMapIndex()
  buildPoiIndex()
  if not q or q == "" then return {} end
  q = q:lower()
  local variantFilter = AM.variantFilter
  local function matchesFilter(rec)
    if not variantFilter then return true end
    if variantFilter.instance_type and rec.instance_type ~= variantFilter.instance_type then return false end
    if variantFilter.timeline and rec.timeline ~= variantFilter.timeline then return false end
    return true
  end
  local function clone(rec)
    local t = {}
    for k,v in pairs(rec) do
      if k == "variants" and type(v) == "table" then
        local list = {}
        for i,r in ipairs(v) do list[i] = clone(r) end
        t.variants = list
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
  local function canonicalize(list)
    if #list == 1 then return list[1], nil end
    local best = list[1]
    for i = 2, #list do
      local r = list[i]
      if AM.preferInstanceMap then
        if r.type == "map" and best.type ~= "map" then
          best = r
        elseif r.type == "map" and best.type == "map" and AM.isInstanceLike and AM.isInstanceLike(r.mapID) and not AM.isInstanceLike(best.mapID) then
          best = r
        end
      else
        if r.type ~= "map" and best.type == "map" then best = r end
      end
    end
    local candidates = {}
    for _, r in ipairs(list) do
      if r ~= best then
        candidates[#candidates+1] = r
        for k, v in pairs(r) do if best[k] == nil then best[k] = v end end
      end
    end
    return best, candidates
  end
  local out = {}
  local seen = {}
  local nameOrder = {}
  local function add(rec)
    if not rec or not rec.name then return end
    local copy = clone(rec)
    local nm = copy.name:lower()
    local expKey = expansionKey(copy)
    if not seen[nm] then
      seen[nm] = { _order = {} }
      nameOrder[#nameOrder+1] = nm
    end
    local groups = seen[nm]
    if not groups[expKey] then
      groups[expKey] = {}
      table.insert(groups._order, expKey)
    end
    table.insert(groups[expKey], copy)
    if rec.variants then
      for _, v in ipairs(rec.variants) do add(v) end
      copy.variants = nil
    end
  end
  -- Prefer exact map name match first
  local exact = AM.mapIndex[q]
  if exact then add(exact) end
  -- Partial map matches
  for name, rec in pairs(AM.mapIndex) do
    if name ~= q and name:find(q, 1, true) then
      add(rec)
    end
  end
  -- POI matches (appended after maps)
  if AM._poiList then
    for _, p in ipairs(AM._poiList) do
      local n = p.name_l or (p.name and p.name:lower())
      if n and n:find(q, 1, true) then
        if p.mapID then
          local info = C_Map.GetMapInfo(p.mapID)
          if info and info.name then
            local key = info.name:lower()
            if not AM.mapIndex[key] then
              AM.mapIndex[key] = {
                mapID = p.mapID,
                name = info.name,
                type = "map",
                expansion_id = p.expansion_id,
                timeline = p.timeline,
                phase_id = p.phase_id,
                phase_group = p.phase_group,
              }
            end
            if key:find(q, 1, true) then
              add(AM.mapIndex[key])
            end
          end
        end
        add(p)
      end
    end
  end
  -- Area name matches (map aliases): try to point to a usable mapID
  local Areas = _G.Areas and _G.Areas.recs
  if Areas then
    local function mapIdForAreaRec(ar)
      if not ar then return nil end
      if ar.map_id then return ar.map_id end
      -- Try to resolve via existing mapIndex by walking up parents
      local seen = {}
      local cur = ar
      for _=1,10 do
        local nm = cur.name and cur.name:lower()
        if nm and AM.mapIndex[nm] and AM.mapIndex[nm].mapID then
          return AM.mapIndex[nm].mapID
        end
        local pid = cur.parent
        if not pid or seen[pid] then break end
        seen[pid] = true
        cur = Areas[pid]
        if not cur then break end
      end
      return nil
    end
    for aid, ar in pairs(Areas) do
      local nm = ar and ar.name
      local nml = nm and nm:lower()
      if nml and nml:find(q, 1, true) then
        local mid = mapIdForAreaRec(ar)
        if mid then
          local x, y
          if ar.continent and ar.wx and ar.wy and AM.WorldToMapXY then
            x, y = AM.WorldToMapXY(ar.continent, ar.wx, ar.wy, mid)
          end
          add({
            type = "map",
            mapID = mid,
            name = nm,
            x = x,
            y = y,
            areaID = aid,
            expansion_id = ar.expansion_id,
            timeline = ar.timeline,
            phase_id = ar.phase_id,
            phase_group = ar.phase_group,
          })
        end
      end
    end
  end
  for _, nm in ipairs(nameOrder) do
    local expGroups = seen[nm]
    if expGroups["e:0"] then
      local target
      for _, k in ipairs(expGroups._order) do if k ~= "e:0" then target = k break end end
      if target then
        for _, r in ipairs(expGroups["e:0"]) do table.insert(expGroups[target], r) end
        expGroups["e:0"] = nil
        for i = #expGroups._order, 1, -1 do
          if expGroups._order[i] == "e:0" then table.remove(expGroups._order, i) break end
        end
      end
    end
    local primary, variants = nil, {}
    for _, expKey in ipairs(expGroups._order) do
      local best, cand = canonicalize(expGroups[expKey])
      if cand and #cand > 0 then best.candidates = cand end
      if not primary then
        primary = best
      else
        variants[#variants+1] = best
      end
    end
    if #variants > 0 then primary.variants = variants end
    out[#out+1] = primary
  end
  -- Filter by requested variant type
  for i = #out, 1, -1 do
    local rec = out[i]
    local vars = rec.variants
    if vars then
      for j = #vars, 1, -1 do
        if not matchesFilter(vars[j]) then table.remove(vars, j) end
      end
    end
    if not matchesFilter(rec) then
      if vars and #vars > 0 then
        local promoted = table.remove(vars, 1)
        for k,v in pairs(promoted) do rec[k] = v end
        rec.variants = vars
      else
        table.remove(out, i)
      end
    end
  end
  table.sort(out, function(a,b)
    -- Keep maps before POIs when names are equal
    if a.name == b.name and a.type ~= b.type then
      return a.type == "map"
    end
    return (a.name or "") < (b.name or "")
  end)
  DBG("searchMaps(%q) -> %d result(s)", q, #out)
  return out
end

AM.mapName = mapName
AM.preload = preload
AM.buildMapIndex = buildMapIndex
AM.searchMaps = searchMaps
AM.findMapIDForAreaName = findMapIDForAreaName
AM.findMapIDForCoords = findMapIDForCoords
