--!strict
-- SongMap registry (AUDIO.md §3.1): generated per-track charts
-- (SongMap_<id>.luau, emitted by roball3d-audio/generate_audio.py) looked
-- up by track id. This module IS the default track's map, so existing
-- SongMap.sectionAtBeat / startBeatFor call sites keep working; per-run
-- code resolves the run's map via
--   SongMap.forTrack(SongMap.trackIdFor(seed, Config.Music.Tracklist))
-- GenCore and MusicController share that pick — same seed -> same track
-- -> same map -> the stamped sections match the heard audio.

local SongMapVaporwave = require(script.Parent.SongMap_vaporwave_loop)
local SongMapNeonDescent = require(script.Parent.SongMap_neon_descent)

export type Section = SongMapVaporwave.Section
export type Map = typeof(SongMapVaporwave)

local maps: { [string]: Map } = {
	vaporwave_loop = SongMapVaporwave,
	neon_descent = SongMapNeonDescent,
}

local SongMap: Map = SongMapVaporwave -- default track = tracklist[1]

function SongMap.forTrack(id: string): Map
	return maps[id] or SongMapVaporwave
end

-- Deterministic seeded pick shared by the generator and the runtime.
function SongMap.trackIdFor(seed: number, tracklist: { string }): string
	return tracklist[seed % #tracklist + 1]
end

return SongMap
