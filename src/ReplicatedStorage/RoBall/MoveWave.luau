--!strict
-- MoveWave (DESIGN.md §8.6): the beat-locked mover waveforms, shared so
-- the two evaluators can't drift — the server steps positions at
-- Movers.StepHz for hazard bookkeeping; the client re-evaluates the
-- same wave every frame (MoverController) for smooth motion.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)

local MoveWave = {}

-- PressRow's dropY wave: a trapezoid pulse — the plate spends most of
-- the cycle raised, drops fast, holds the lethal window, then rises.
-- The readable hold IS the timing lesson.
function MoveWave.pressPulse(x: number): number
	local D, H, U = Config.Movers.PressDownFrac, Config.Movers.PressHoldFrac, Config.Movers.PressUpFrac
	if x < D then
		return x / D
	elseif x < D + H then
		return 1
	elseif x < D + H + U then
		return 1 - (x - D - H) / U
	end
	return 0
end

return MoveWave
