--!strict
-- GenVerify (DESIGN.md §8.6): solvability audit. Walks GenCore across
-- seeds and asserts the fairness invariants every builder promises:
--   * chunk-to-chunk entry continuity (the closure contract)
--   * every lethal row leaves a corridor >= Obstacles.CorridorMin
--   * lethal rows spaced >= the 0.45x reaction-time floor
--   * void spans are ballistically clearable at the entry speed
--   * LaunchPad kicks satisfy the strip-clearance closed form
--   * mover sweeps (Rotor) keep a permanent far-side corridor
--   * debut-gated types never appear before their milestone
-- Pure: no Instances, no math.random — same determinism as GenCore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.RoBall.Config)
local Tiers = require(ReplicatedStorage.RoBall.Tiers)
local GenCore = require(ReplicatedStorage.RoBall.GenCore)
local ChunkDefs = require(ReplicatedStorage.RoBall.ChunkDefs)

local GRAV = 196.2
local ROW_T_EPS = 0.03 -- obstacles within this t share one lethal row
local SPACING_FLOOR = 0.45 -- fraction of speed*ReactionTime rows may use (weave rule)

type ISet = { { lo: number, hi: number } }

-- Interval-set helpers for the lateral-reachability audit: `reach` is the
-- set of lane-local x positions the ball can still occupy at the current
-- sample. Expansion adds MaxLateralSpeed-per-stud of travel on both ends;
-- void spans expand without intersecting (an airborne ball still steers).
local function expandSet(set: ISet, d: number): ISet
	local grown = {}
	for _, iv in ipairs(set) do
		table.insert(grown, { lo = iv.lo - d, hi = iv.hi + d })
	end
	table.sort(grown, function(a, b)
		return a.lo < b.lo
	end)
	local merged = {}
	for _, iv in ipairs(grown) do
		local last = merged[#merged]
		if last and iv.lo <= last.hi then
			last.hi = math.max(last.hi, iv.hi)
		else
			table.insert(merged, iv)
		end
	end
	return merged
end

local function intersectSet(a: ISet, b: ISet): ISet
	local out = {}
	local i, j = 1, 1
	while i <= #a and j <= #b do
		local lo = math.max(a[i].lo, b[j].lo)
		local hi = math.min(a[i].hi, b[j].hi)
		if lo < hi then
			table.insert(out, { lo = lo, hi = hi })
		end
		if a[i].hi < b[j].hi then
			i += 1
		else
			j += 1
		end
	end
	return out
end

-- Remove a blocked x-span from every interval in the set (lethal blocks
-- shrink the valid band over their depth — the ball threads the corridor,
-- which is exactly what the next chunk's transitions must survive).
local function subtractSpan(set: ISet, lo: number, hi: number): ISet
	local out = {}
	for _, iv in ipairs(set) do
		if hi <= iv.lo or lo >= iv.hi then
			table.insert(out, iv)
		else
			if lo > iv.lo then
				table.insert(out, { lo = iv.lo, hi = math.min(iv.hi, lo) })
			end
			if hi < iv.hi then
				table.insert(out, { lo = math.max(iv.lo, hi), hi = iv.hi })
			end
		end
	end
	return out
end

export type Report = {
	seed: number,
	chunks: number,
	violations: { string },
	counts: { [string]: number },
	firstSeen: { [string]: number },
}

local GenVerify = {}

local function ballisticsClear(gapLen: number, entrySpeed: number, vy0: number, dropH: number): boolean
	-- Time to fall `dropH` below the lip with launch vy0 (constant forward
	-- speed — the drive loop writes -fwd every frame even airborne).
	local tAir = (vy0 + math.sqrt(vy0 * vy0 + 2 * GRAV * math.max(dropH, 0))) / GRAV
	return gapLen <= entrySpeed * tAir + 3 -- 3 studs slack for arc flare
end

-- Largest clear lateral gap in the deck at a lethal row. SlideX movers
-- shift both blocks together so their fixed gap is preserved — static
-- coverage at rest is the right check. Spin arms (Rotor) are timed, not
-- corridor geometry — they get a dedicated disc-bound check instead.
local function rowCorridor(row: { ChunkDefs.Obstacle }, halfW: number): number
	local spans = {}
	for _, ob in ipairs(row) do
		local isTooth = ob.hang == true and ob.h <= Config.Tunnel.ToothMax + 0.01
		local isArm = ob.motion ~= nil and ob.motion.kind == "spin"
		if not isTooth and not isArm then
			table.insert(spans, { lo = ob.xOff - ob.w / 2, hi = ob.xOff + ob.w / 2 })
		end
	end
	table.sort(spans, function(a, b)
		return a.lo < b.lo
	end)
	local best = 0
	local edge = -halfW
	for _, s in ipairs(spans) do
		best = math.max(best, math.min(s.lo, halfW) - edge)
		edge = math.max(edge, s.hi)
	end
	best = math.max(best, halfW - edge)
	return best
end

function GenVerify.sweep(seed: number, nChunks: number): Report
	local gen = GenCore.new(seed)
	local violations = {}
	local counts: { [string]: number } = {}
	local firstSeen: { [string]: number } = {}
	local prevEnd: { width: number, centerX: number, y: number }? = nil
	local reach: ISet? = nil -- reachable lateral band at the current sample
	local dist = 0

	local function bad(msg: string, spec: ChunkDefs.ChunkSpec, i: number)
		table.insert(violations, string.format("[s%d c%d %s] %s", seed, i, spec.type, msg))
	end

	for i = 1, nChunks do
		local spec = gen:nextChunk()
		counts[spec.type] = (counts[spec.type] or 0) + 1
		local baseType = spec.type:gsub("^Intro_", "")
		if not firstSeen[baseType] then
			firstSeen[baseType] = dist
		end

		-- Entry continuity: section(0) must equal the previous endState.
		local s0 = spec.section(0)
		if
			prevEnd
			and (
				math.abs(s0.width - prevEnd.width) > 0.6
				or math.abs(s0.centerX - prevEnd.centerX) > 0.6
				or math.abs(s0.y - prevEnd.y) > 0.6
			)
		then
			bad(
				string.format(
					"entry mismatch w %.1f->%.1f x %.1f->%.1f y %.1f->%.1f",
					prevEnd.width,
					s0.width,
					prevEnd.centerX,
					s0.centerX,
					prevEnd.y,
					s0.y
				),
				spec,
				i
			)
		end
		prevEnd = spec.endState

		-- Flat-exit contract: roll, cutout, walls and roof are chunk-internal —
		-- every chunk must hand the next a level, open seam. A non-flat entry
		-- means the previous chunk's exit broke the convention.
		if math.abs(s0.rollDeg) > 0.5 or (s0.cutout or 0) > 0.5 or (s0.wallH or 0) > 0.5 or (s0.roofH or 0) > 0.5 then
			bad(
				string.format(
					"non-flat entry: roll %.2f cut %.2f wall %.2f roof %.2f",
					s0.rollDeg,
					s0.cutout or 0,
					s0.wallH or 0,
					s0.roofH or 0
				),
				spec,
				i
			)
		end

		-- Section sweep: sanity + void spans + ballistic clearance.
		local N = 24
		local voidT0: number? = nil
		local voidLipY = 0
		local voidLipSlope = 0
		local reachFlagged = false
		local halfR = Config.Ball.Diameter / 2

		-- Static lethal blockers for the reachability band: at a row's
		-- depth the ball can only occupy the corridor gaps, which shapes
		-- what the next chunk must survive. Movers and tunnel teeth are
		-- timing/decoration, and pad chunks exempt their strip — the
		-- crossing is airborne (the kick audit owns it).
		local blockers: { { t0: number, t1: number, xOff: number, hw: number } } = {}
		if spec.obstacles then
			local stripHMax = Config.Pads.StripH + 0.01
			for _, ob in ipairs(spec.obstacles) do
				local isTooth = ob.hang == true and ob.h <= Config.Tunnel.ToothMax + 0.01
				local isMover = ob.motion ~= nil
				local isStrip = spec.pads ~= nil and ob.h <= stripHMax
				if not (isTooth or isMover or isStrip) then
					local zHalf = ob.d / (2 * spec.length)
					table.insert(blockers, { t0 = ob.t - zHalf, t1 = ob.t + zHalf, xOff = ob.xOff, hw = ob.w / 2 })
				end
			end
		end

		for k = 0, N do
			local t = k / N
			local s = spec.section(t)
			if s.width ~= s.width or s.y ~= s.y then
				bad("NaN section", spec, i)
				break
			end

			-- Lateral reachability: does any survivable line still exist?
			-- The valid band is the ribbon minus ball radius, split into
			-- rails by cutouts and shrunk around lethal blockers; an empty
			-- reach set = geometry the player cannot possibly survive — an
			-- impossible seam, not player error.
			local valid: ISet = {}
			if s.width > 0.5 then
				local eL = s.centerX - s.width / 2 + halfR
				local eR = s.centerX + s.width / 2 - halfR
				local cut = s.cutout or 0
				if cut > 1 then
					local off = s.cutoutOff or 0
					local cL = s.centerX + off - cut / 2 - halfR
					local cR = s.centerX + off + cut / 2 + halfR
					if eL < cL then
						table.insert(valid, { lo = eL, hi = cL })
					end
					if cR < eR then
						table.insert(valid, { lo = cR, hi = eR })
					end
				elseif eL < eR then
					table.insert(valid, { lo = eL, hi = eR })
				end
				for _, bl in ipairs(blockers) do
					if t >= bl.t0 and t <= bl.t1 then
						valid = subtractSpan(
							valid,
							s.centerX + bl.xOff - bl.hw - halfR,
							s.centerX + bl.xOff + bl.hw + halfR
						)
					end
				end
			end
			-- Lateral budget at the SLOWEST survivable entry — a braked ball
			-- gets the most sideways room per stud, so a line only flagged
			-- here is impossible at ANY entry speed, not just nominal.
			local stepZ = (spec.length / N)
				* Config.Steering.MaxLateralSpeed
				/ math.max(Tiers.speedAt(dist + t * spec.length) * Config.Pads.SlowCrossFrac, 1)
			if not reach then
				reach = valid
			else
				reach = expandSet(reach, stepZ)
				if #valid > 0 then
					reach = intersectSet(reach, valid)
					if #reach == 0 and not reachFlagged then
						reachFlagged = true
						bad(string.format("no reachable line through deck at t=%.2f", t), spec, i)
						-- Revive on the valid band so later samples/chunks
						-- audit independently instead of re-flagging the
						-- same death forever.
						reach = valid
					end
				end
			end

			if s.width < -0.01 then
				bad(string.format("negative width %.2f at t=%.2f", s.width, t), spec, i)
			end
			if s.width > 0.5 and s.width < 2.5 then
				bad(string.format("razor width %.2f at t=%.2f", s.width, t), spec, i)
			end
			if s.width <= 0.5 then
				if not voidT0 then
					voidT0 = t
					local sPrev = spec.section(math.max(t - 1 / N, 0))
					local sPrev2 = spec.section(math.max(t - 2 / N, 0))
					voidLipY = sPrev.y
					-- Rise-per-stud at the lip — a launch ramp's positive
					-- slope becomes the ballistic vy0 (v stays constant;
					-- only Y is ballistic in this model).
					voidLipSlope = math.max((sPrev.y - sPrev2.y) * N / spec.length, 0)
				end
			elseif voidT0 then
				local gapLen = (t - voidT0) * spec.length
				local speed = Tiers.speedAt(dist + voidT0 * spec.length)
				local vy0: number
				if spec.pads and #spec.pads > 0 then
					vy0 = spec.pads[1].kickY
				else
					vy0 = speed * voidLipSlope / math.sqrt(1 + voidLipSlope * voidLipSlope)
				end
				-- OrbHop's void is intentionally NOT pad-clearable — the orb
				-- is mandatory. The dedicated orb check below owns it.
				if not (spec.orbs and #spec.orbs > 0) and not ballisticsClear(gapLen, speed, vy0, voidLipY - s.y) then
					bad(
						string.format("void %.1f studs may be unclearable at %.0f s/s (vy0 %.1f)", gapLen, speed, vy0),
						spec,
						i
					)
				end
				voidT0 = nil
			end
		end

		-- Lethal rows: corridor + spacing between consecutive rows.
		if spec.obstacles and #spec.obstacles > 0 then
			local sorted = table.clone(spec.obstacles)
			table.sort(sorted, function(a, b)
				return a.t < b.t
			end)
			local rows: { { ChunkDefs.Obstacle } } = {}
			for _, ob in ipairs(sorted) do
				local row = rows[#rows]
				if row and math.abs(row[1].t - ob.t) <= ROW_T_EPS then
					table.insert(row, ob)
				else
					table.insert(rows, { ob })
				end
			end
			local prevT: number? = nil
			for _, row in ipairs(rows) do
				-- Rows that are ALL decorative tunnel teeth are overhead
				-- dressing (bottom edge hangs above the ball's reach) —
				-- not a navigational read, so they exempt corridor+spacing.
				local allTeeth = true
				local stripRow = true
				for _, ob in ipairs(row) do
					local isTooth = ob.hang == true and ob.h <= Config.Tunnel.ToothMax + 0.01
					if not isTooth then
						allTeeth = false
					end
					if ob.h > Config.Pads.StripH + 0.01 then
						stripRow = false
					end
				end
				if allTeeth then
					continue
				end
				local t = row[1].t
				local s = spec.section(math.clamp(t, 0, 1))
				local halfW = s.width / 2
				-- PadHop's lethal strip is a vertical corridor (the kick
				-- check below covers it) — no lateral gap required.
				if halfW > 1 and not (spec.pads and stripRow) then
					local corr = rowCorridor(row, halfW)
					if corr < Config.Obstacles.CorridorMin - 0.05 then
						bad(string.format("corridor %.2f < min at t=%.2f", corr, t), spec, i)
					end
				end
				-- Rotor disc bound: far-side corridor must survive the sweep.
				for _, ob in ipairs(row) do
					if ob.motion and ob.motion.kind == "spin" then
						local r = ob.w / 2
						local far = if ob.xOff < 0 then halfW - (ob.xOff + r) else (ob.xOff - r) + halfW
						if far < Config.Obstacles.CorridorMin - 0.05 then
							bad(string.format("rotor disc swallows corridor (%.2f)", far), spec, i)
						end
					end
				end
				if prevT then
					local gapZ = (t - prevT) * spec.length
					local speed = Tiers.speedAt(dist + t * spec.length)
					if gapZ < speed * Config.Obstacles.ReactionTime * SPACING_FLOOR then
						bad(string.format("rows %.1f studs apart at %.0f s/s", gapZ, speed), spec, i)
					end
				end
				prevT = t
			end
		end

		-- OrbHop (§8.6 stretch): two-arc audit.
		--   1. The pad arc must pass within orb.radius of the orb — the tap
		--      target is actually reachable.
		--   2. The orb's re-kick must cover the remaining gap to the landing.
		--   3. The pad arc ALONE must fall short — orb-or-die, not
		--      orb-or-also-fine.
		if spec.orbs and #spec.orbs > 0 and spec.pads and #spec.pads > 0 then
			local pad = spec.pads[1]
			local orb = spec.orbs[1]
			local speed = Tiers.speedAt(dist + pad.t * spec.length)
			local orbD = (orb.t - pad.t) * spec.length
			local grade = Config.Generation.Grade
			-- orb.yOff is measured from the graded void plane at orb.t;
			-- height above the pad deck is yOff - grade*orbD.
			local orbAbovePad = orb.yOff - grade * orbD
			local tOrb = orbD / speed
			local hAtOrb = pad.kickY * tOrb - GRAV * tOrb * tOrb / 2
			if math.abs(hAtOrb - orbAbovePad) > orb.radius then
				bad(
					string.format("orb unreachable: arc h %.1f vs orb %.1f at %.0f studs", hAtOrb, orbAbovePad, orbD),
					spec,
					i
				)
			end
			-- Remaining gap orb -> landing lip: scan the section for the
			-- void's end past the orb.
			local landD: number? = nil
			for k = 0, 48 do
				local t = pad.t + (k / 48) * (1 - pad.t)
				if t > orb.t and spec.section(t).width > 0.5 then
					landD = (t - pad.t) * spec.length
					break
				end
			end
			if not landD then
				bad("no landing after orb", spec, i)
			else
				local sLand = spec.section(pad.t + landD / spec.length)
				local sPad = spec.section(pad.t)
				local drop = orbAbovePad + (sPad.y - sLand.y)
				if not ballisticsClear(landD - orbD, speed, orb.kickY, drop) then
					bad(
						string.format("orb kick %.1f cannot reach landing %.0f studs out", orb.kickY, landD - orbD),
						spec,
						i
					)
				end
				-- The pad arc alone must NOT clear the whole gap.
				if ballisticsClear(landD, speed, pad.kickY, sPad.y - sLand.y) then
					bad("pad arc clears gap alone — orb not mandatory", spec, i)
				end
			end
		end

		-- FlipRide (§8.6 stretch): zone geometry sanity — react runway
		-- before entry, a real ride span, and enough clearance for the ball.
		if spec.flip then
			local f = spec.flip
			if f.t0 < 0.12 then
				bad(string.format("flip zone starts too soon (t0 %.2f)", f.t0), spec, i)
			end
			if (f.t1 - f.t0) * spec.length < 20 then
				bad(string.format("flip ride %.0f studs < 20", (f.t1 - f.t0) * spec.length), spec, i)
			end
			if f.clearH < 4 then
				bad(string.format("flip clearance %.1f < ball + margin", f.clearH), spec, i)
			end
			local sMid = spec.section((f.t0 + f.t1) / 2)
			if sMid.width < Config.Obstacles.CorridorMin then
				bad(string.format("flip corridor width %.1f too narrow", sMid.width), spec, i)
			end
		end

		-- LaunchPad kick: the strip must sit INSIDE the intersection of
		-- above-h windows across the survivable entry-speed range
		-- [SlowCrossFrac, Power.Mult]*speed — a braked or boosted entry
		-- otherwise meets an arc it cannot clear.
		if spec.pads and spec.type == "PadHop" then
			local speed = Tiers.speedAt(dist + spec.pads[1].t * spec.length)
			local strip = spec.obstacles and spec.obstacles[1]
			local pad = spec.pads[1]
			if strip then
				local tApex = pad.kickY / GRAV
				local wSec = 2
					* math.sqrt(
						math.max(
							pad.kickY * pad.kickY / (GRAV * GRAV) - 2 * (strip.h + Config.Pads.ArcMargin) / GRAV,
							0
						)
					)
				local zLo = Config.Power.Mult * speed * (tApex - wSec / 2)
				local zHi = Config.Pads.SlowCrossFrac * speed * (tApex + wSec / 2)
				local stripZ = strip.t * spec.length - pad.t * spec.length
				if stripZ - strip.d / 2 < zLo - 0.5 or stripZ + strip.d / 2 > zHi + 0.5 then
					bad(
						string.format(
							"strip [%.1f..%.1f] escapes clearance window [%.1f..%.1f] (kickY %.1f)",
							stripZ - strip.d / 2,
							stripZ + strip.d / 2,
							zLo,
							zHi,
							pad.kickY
						),
						spec,
						i
					)
				end
			end
		end

		dist += spec.length
	end

	-- Debut gate: a gated type's first appearance must be at/after its
	-- milestone (the debut distance is checked against chunk START dist).
	for name, debutDist in pairs(Config.Features.Debut) do
		local seen = firstSeen[name]
		if seen and seen < debutDist - 1 then
			table.insert(violations, string.format("%s appeared at %.0fm before debut %dm", name, seen, debutDist))
		end
	end

	return { seed = seed, chunks = nChunks, violations = violations, counts = counts, firstSeen = firstSeen }
end

function GenVerify.sweepRange(seed0: number, seedCount: number, nChunks: number): { Report }
	local out = {}
	for s = seed0, seed0 + seedCount - 1 do
		table.insert(out, GenVerify.sweep(s, nChunks))
	end
	return out
end

return GenVerify
