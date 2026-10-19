--!strict
-- MusicGrid (AUDIO.md §5.2): the musical clock as pure math.
--
-- The heard tempo is BaseBpm * PlaybackSpeed and PlaybackSpeed rides the
-- same speed curve the ball does, so the number of song-beats elapsed at a
-- given track distance is a pure function of the nominal speed schedule —
-- no wall clock, no audio thread. GenCore accumulates it per chunk to give
-- the generator a section/phrase position for any distance.
--
-- Honest limit (AUDIO.md §5.2): this predicts the NOMINAL speed profile
-- (Tiers.speedAt). A player holding W/S drifts the heard position vs the
-- predicted one — bounded, and the grid re-converges every loop lap.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local SongMap = require(ReplicatedStorage.RoBall.SongMap)

local MusicGrid = {}

local m = Config.Music

-- PlaybackSpeed the music runs at while the ball travels `speed` studs/s —
-- the same mapping MusicController applies live.
function MusicGrid.playbackSpeedAt(speed: number): number
	local norm = math.clamp((speed - Config.Speed.Start) / (Config.Speed.Max - Config.Speed.Start), 0, 1)
	return m.PlaybackSpeedMin + (m.PlaybackSpeedMax - m.PlaybackSpeedMin) * norm
end

-- Song-beats elapsed per stud traveled at `speed` studs/s:
-- heard beats/s = bpm*ps(v)/60, and the ball covers v studs in that second.
-- `bpm` is the run map's tempo; falls back to the default track's.
function MusicGrid.beatsPerStud(speed: number, bpm: number?): number
	return (bpm or m.BaseBpm) * MusicGrid.playbackSpeedAt(speed) / (60 * speed)
end

local STEP = 5 -- studs per integration step

-- Beats elapsed rolling from d0 to d1 studs on the nominal tier schedule.
-- Midpoint sampling per STEP — at ~0.02-0.03 beats/stud the error vs the
-- exact integral is far under a beat per chunk.
function MusicGrid.beatsBetween(d0: number, d1: number, bpm: number?): number
	if d1 <= d0 then
		return 0
	end
	local beats = 0
	local d = d0
	while d < d1 do
		local nxt = math.min(d + STEP, d1)
		beats += MusicGrid.beatsPerStud(Tiers.speedAt((d + nxt) / 2), bpm) * (nxt - d)
		d = nxt
	end
	return beats
end

-- Standalone position lookup (client HUD, tests). GenCore uses the
-- incremental beatsBetween instead of re-integrating from zero per chunk.
function MusicGrid.beatPosAt(dist: number, bpm: number?): number
	return MusicGrid.beatsBetween(0, dist, bpm)
end

function MusicGrid.sectionAtBeat(beatPos: number): SongMap.Section
	return SongMap.sectionAtBeat(beatPos)
end

function MusicGrid.sectionAt(dist: number): SongMap.Section
	return SongMap.sectionAtBeat(MusicGrid.beatPosAt(dist))
end

return MusicGrid
