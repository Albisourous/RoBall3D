--!strict
-- SongMap registry (AUDIO.md §3.1): generated per-track charts
-- (SongMap_<id>.luau — FlowMusic renders by import_flowmusic.py) looked
-- up by track id. This module IS the parked track's map, so existing
-- SongMap.sectionAtBeat / startBeatFor call sites keep working; per-run
-- code resolves the run's map via
--   SongMap.forTrack(SongMap.trackIdFor(seed, Config.Music.ActiveTracklist))
-- GenCore and MusicController share that pick — same seed -> same track
-- -> same map -> the stamped sections match the heard audio.

local SongMapPalmScreens = require(script.Parent.SongMap_palm_screens)

export type Section = SongMapPalmScreens.Section
export type Map = typeof(SongMapPalmScreens)

local maps: { [string]: Map } = {
	-- FlowMusic catalog (roball3d-audio/flowmusic/)
	midnight_overdrive = require(script.Parent.SongMap_midnight_overdrive),
	void_runner = require(script.Parent.SongMap_void_runner),
	tape_drift = require(script.Parent.SongMap_tape_drift),
	smoothride = require(script.Parent.SongMap_smoothride),
	retro_wave_sunset = require(script.Parent.SongMap_retro_wave_sunset),
	neon_nostalgia = require(script.Parent.SongMap_neon_nostalgia),
	oldtimes = require(script.Parent.SongMap_oldtimes),
	underwater = require(script.Parent.SongMap_underwater),
	velvet_loader = require(script.Parent.SongMap_velvet_loader),
	palm_screens = SongMapPalmScreens,
}

local SongMap: Map = SongMapPalmScreens -- parked = the menu bed

function SongMap.forTrack(id: string): Map
	return maps[id] or SongMapPalmScreens
end

-- Deterministic seeded pick shared by the generator and the runtime.
function SongMap.trackIdFor(seed: number, tracklist: { string }): string
	if #tracklist == 0 then
		return "palm_screens" -- empty ActiveTracklist (every AssetId unwired)
	end
	return tracklist[seed % #tracklist + 1]
end

return SongMap
