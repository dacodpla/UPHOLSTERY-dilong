-- Central balance configuration. All tunable numbers live here.
-- Never hardcode these values inside logic scripts.

return {

	-- =========================================================
	-- MINIGAME SHARED
	-- =========================================================
	Minigame = {
		-- Multiplier applied to precision windows when a job has the Fragile modifier.
		-- Values < 1 make the window smaller (harder). 0.6 = 40% tighter.
		fragileMultiplier = 0.6,

		-- Additional tolerance granted by tool upgrades (additive, 0.0–1.0 range).
		-- 0.0 = no bonus, 0.2 = 20% wider tolerance.
		toolToleranceBonus = {
			curvedNeedle  = 0.20,   -- widens SeamStitching deviation tolerance
			foamPressKit  = 0.20,   -- widens FoamPadding snap tolerance
		},
	},

	-- =========================================================
	-- TACK REMOVAL  (osu!-style)
	-- =========================================================
	TackRemoval = {
		tackCountMin       = 8,    -- minimum tacks per run
		tackCountMax       = 14,   -- maximum tacks per run
		approachTime       = 2.0,  -- seconds for approach ring to shrink to tack
		tackSpawnGap       = 0.85, -- seconds between each tack appearing
		-- Timing windows: progress = elapsed / approachTime at moment of click (0→1)
		perfectMinProgress = 0.72, -- click in last 28% of approach = perfect (3 pts)
		goodMinProgress    = 0.42, -- click in last 58% of approach = good    (2 pts)
		--                           click earlier = ok (1 pt), no click = miss (0 pts)
		-- Result thresholds (score / maxScore where maxScore = tackCount * 3)
		perfectMinScore    = 0.78,
		goodMinScore       = 0.45,
	},

	-- =========================================================
	-- STAPLE GUNNING  (multi-zone)
	-- =========================================================
	StapleGunning = {
		stapleCountMin   = 6,
		stapleCountMax   = 10,
		zoneCount        = 3,      -- number of zone pairs scattered on the track
		goodZoneWidth    = 0.11,   -- outer green zone width (smaller = harder)
		perfectZoneWidth = 0.050,  -- inner gold zone width (very narrow)
		barSpeed         = 0.62,   -- fast base speed
		barSpeedRampUp   = 0.040,  -- speed added per successful staple
		timeLimit        = 30,
		-- Score: perfect = 2 pts, good = 1 pt, miss = 0. maxScore = stapleCount * 2
		perfectMinRatio  = 0.75,   -- relaxed slightly since zones are harder
		goodMinRatio     = 0.38,
	},

	-- =========================================================
	-- SEAM STITCHING  (free drag, no snap)
	-- =========================================================
	SeamStitching = {
		segmentCountMin         = 5,    -- longer path
		segmentCountMax         = 7,
		timePerSegment          = 9,    -- seconds per segment (total = segCount * timePerSegment)
		deviationTolerance      = 32,   -- slightly more forgiving since no snap
		perfectMaxDeviationFrac = 0.35,
		goodMaxDeviationFrac    = 0.70,
		trailLength             = 36,
	},

	-- =========================================================
	-- FOAM PADDING  (random shapes)
	-- =========================================================
	FoamPadding = {
		pieceCount      = 3,
		timeLimit       = 40,
		snapTolerance   = 32,
		-- Result thresholds (ratio of pieces correctly snapped)
		perfectMinRatio = 1.0,
		goodMinRatio    = 0.67,
	},

	-- =========================================================
	-- JOB ECONOMY  (referenced later by the Job System)
	-- =========================================================
	Economy = {
		payByTier = {
			Starter  = { min = 50,    max = 150   },
			Mid      = { min = 200,   max = 500   },
			Premium  = { min = 600,   max = 1200  },
			Prestige = { min = 1500,  max = 3000  },
		},
		premiumPayMultiplierMin = 1.8,
		premiumPayMultiplierMax = 2.5,
		hotJobPayMultiplier     = 3.0,
		dailyOverheadCoins      = 120,
	},

	-- =========================================================
	-- FOLLOWER SYSTEM  (referenced later by the Follower module)
	-- =========================================================
	Followers = {
		baseGainPerJob = 10,
		photoBonus = {
			centeringMin = 0.10,
			centeringMax = 0.25,
			lightAngleMin = 0.05,
			lightAngleMax = 0.15,
		},
		minigameBonus = {
			Pass    = 0.00,
			Good    = 0.10,
			Perfect = 0.25,
		},
		premiumJobBonus  = 0.40,
		hotJobBonus      = 0.75,
		storyJobBonus    = 0.20,
	},

	-- =========================================================
	-- LIVE JOB BOARD  (referenced later by the Job Board module)
	-- =========================================================
	JobBoard = {
		poolSizeMin        = 8,
		poolSizeMax        = 12,
		poolSizeLowPlayer  = { min = 4, max = 6 },  -- fewer than 4 active players
		lowPlayerThreshold = 4,
		replenishMin       = 90,    -- seconds between new job generation (min)
		replenishMax       = 120,   -- seconds between new job generation (max)
		tombstoneDuration  = 3,     -- seconds "Taken by X" remains visible
		premiumRollChance  = 1/6,   -- ~16.7% of generated jobs are Premium
		hotJobIntervalMin  = 5 * 60,  -- 5 minutes in seconds
		hotJobIntervalMax  = 8 * 60,  -- 8 minutes in seconds
		hotJobCountdown    = 10,    -- seconds of countdown before Hot Job is claimable
		disconnectGraceSec = 60,    -- seconds before abandoned job re-enters pool
	},

	-- =========================================================
	-- FEEDSTITCH
	-- =========================================================
	FeedStitch = {
		commentMaxLength   = 80,
		commentsPerPlayer  = 3,
		popularLikeCount   = 5,    -- likes needed for "Popular" tag
		bestPostIntervalSec = 2 * 60 * 60,  -- 2 hours
		tierTitles = {
			Perfect = "Just nailed a perfect %s! ✨",
			Good    = "Knocked out a solid %s!",
			Pass    = "Got through a %s.",
			Fail    = "Struggled with a %s today...",
		},
	},
}
