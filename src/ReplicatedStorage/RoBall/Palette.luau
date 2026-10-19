--!strict
-- Palette (DESIGN.md §8.5): a single hue wheel cycled by distance. Edges,
-- gems, grid lines and tower outlines all sample it so the scene laps
-- lime -> green -> emerald as you go deeper — always the green family.

local Config = require(script.Parent.Config)

local Palette = {}

local stops = Config.Palette.HueStops

-- Hue in degrees [0,360) at `dist` meters into a run.
function Palette.hueAt(dist: number): number
	local cycle = (math.max(dist, 0) / Config.Palette.CycleDistance) % 1
	local seg = cycle * (#stops - 1)
	local i = math.floor(seg)
	local f = seg - i
	return stops[i + 1] + (stops[i + 2] - stops[i + 1]) * f
end

-- Full-neon swatch at `dist`. Feeds edge rails, accents, backdrop.
function Palette.neonAt(dist: number): Color3
	return Color3.fromHSV(Palette.hueAt(dist) / 360, Config.Palette.Saturation, Config.Palette.NeonValue)
end

-- Dimmer variant for silhouettes (mountain wireframes, walls).
function Palette.dimAt(dist: number, valueScale: number): Color3
	return Color3.fromHSV(
		Palette.hueAt(dist) / 360,
		Config.Palette.Saturation,
		Config.Palette.NeonValue * math.clamp(valueScale, 0, 1)
	)
end

return Palette
