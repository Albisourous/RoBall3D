--!strict
-- GenVerify runner (DESIGN.md §8.6): Studio-only solvability sweep. With
-- Config.Debug.VerifySeeds > 0, walks N seeds through GenCore on boot and
-- prints every fairness violation found. Inert in production servers and
-- when the flag is 0.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not RunService:IsStudio() then
	return
end

local Config = require(ReplicatedStorage.RoBall.Config)
if (Config.Debug.VerifySeeds or 0) <= 0 then
	return
end

local GenVerify = require(ReplicatedStorage.RoBall.GenVerify)

task.defer(function()
	local reports = GenVerify.sweepRange(1, Config.Debug.VerifySeeds, Config.Debug.VerifyChunks)
	local totalViol = 0
	for _, r in ipairs(reports) do
		totalViol += #r.violations
		if #r.violations > 0 then
			warn(string.format("[GenVerify] seed %d: %d violation(s)", r.seed, #r.violations))
			for _, msg in ipairs(r.violations) do
				warn("   ", msg)
			end
		end
	end
	-- GradeFloor probe (§8.1): the range sweep never reaches the descent
	-- floor, so walk one seed the full ~290km — audits every chunk through
	-- the level-off and asserts the deck stays clear of the kill plane.
	local probe, reached = GenVerify.floorProbe(1)
	totalViol += #probe.violations
	for _, msg in ipairs(probe.violations) do
		warn("   ", "[floor-probe] " .. msg)
	end
	print(
		string.format(
			"[GenVerify] sweep complete: %d seeds x %d chunks, %d violation(s); floor-probe %s (endY %.0f, floor %.0f)",
			#reports,
			Config.Debug.VerifyChunks,
			totalViol,
			if reached then "reached GradeFloor" else "DID NOT reach GradeFloor",
			probe.endY,
			Config.Generation.GradeFloor
		)
	)
end)
