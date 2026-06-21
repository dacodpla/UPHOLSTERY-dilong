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
		toolToleranceBonus = {
			curvedNeedle  = 0.20,   -- widens SeamStitching deviation tolerance
			foamPressKit  = 0.20,   -- widens FoamPadding snap tolerance
		},
	},

	-- =========================================================
	-- TACK REMOVAL  (osu!-style)
	-- =========================================================
	TackRemoval = {
		tackCountMin       = 8,
		tackCountMax       = 14,
		approachTime       = 2.0,
		tackSpawnGap       = 0.85,
		perfectMinProgress = 0.72,
		goodMinProgress    = 0.42,
		perfectMinScore    = 0.78,
		goodMinScore       = 0.45,
	},

	-- =========================================================
	-- STAPLE GUNNING  (multi-zone)
	-- =========================================================
	StapleGunning = {
		stapleCountMin   = 6,
		stapleCountMax   = 10,
		zoneCount        = 3,
		goodZoneWidth    = 0.11,
		perfectZoneWidth = 0.050,
		barSpeed         = 0.62,
		barSpeedRampUp   = 0.040,
		timeLimit        = 30,
		perfectMinRatio  = 0.75,
		goodMinRatio     = 0.38,
	},

	-- =========================================================
	-- SEAM STITCHING  (free drag, no snap)
	-- =========================================================
	SeamStitching = {
		segmentCountMin         = 5,
		segmentCountMax         = 7,
		timePerSegment          = 9,
		deviationTolerance      = 32,
		perfectMaxDeviationFrac = 0.35,
		goodMaxDeviationFrac    = 0.70,
		trailLength             = 36,
	},

	-- =========================================================
	-- FOAM PADDING  (random shapes)
	-- =========================================================
	FoamPadding = {
		pieceCount      = 5,
		timeLimit       = 50,
		perfectMinRatio = 1.0,
		goodMinRatio    = 0.75,
	},

	-- =========================================================
	-- JOB ECONOMY
	-- =========================================================
	Economy = {
		payByTier = {
			Starter   = { min = 50,    max = 150   },
			Mid       = { min = 200,   max = 500   },
			Premium   = { min = 600,   max = 1200  },
			Prestige  = { min = 1500,  max = 3000  },
			Exclusive = { min = 3500,  max = 7000  },
			Elite     = { min = 7500,  max = 15000 },
			Special   = { min = 15000, max = 30000 },
		},
		hotJobPayMultiplier  = 3.0,
		dailyOverheadCoins   = 120,
	},

	-- =========================================================
	-- FOLLOWER SYSTEM
	-- =========================================================
	Followers = {
		gainByTier = {
			Starter   = { min = 6,    max = 15   },
			Mid       = { min = 18,   max = 35   },
			Premium   = { min = 45,   max = 80   },
			Prestige  = { min = 90,   max = 150  },
			Exclusive = { min = 180,  max = 320  },
			Elite     = { min = 400,  max = 650  },
			Special   = { min = 800,  max = 1200 },
		},
		minigameBonus = {
			Pass    = 0.00,
			Good    = 0.10,
			Perfect = 0.25,
		},
		hotJobBonus   = 0.75,
		storyJobBonus = 0.20,
	},

	-- =========================================================
	-- LIVE JOB BOARD
	-- =========================================================
	JobBoard = {
		poolSizeMin       = 4,    -- floor: solo player still gets some variety
		poolSizeMax       = 12,   -- cap: full server
		poolSizePerPlayer = { min = 1.5, max = 2.5 },  -- jobs generated per player in server
		replenishMin      = 15,   -- seconds between global pool refreshes (min)
		replenishMax      = 30,   -- seconds between global pool refreshes (max)
		tombstoneDuration = 3,    -- seconds "Taken by X" remains visible (client-side)
		hotJobIntervalMin  = 5 * 60,
		hotJobIntervalMax  = 8 * 60,
		hotJobCountdown    = 10,
		disconnectGraceSec = 60,
	},

	-- =========================================================
	-- JOB TIER RARITY  (relative weights for the global board)
	-- All players see the same pool; higher tiers appear less often.
	-- These are summed and treated as a weighted random distribution.
	-- =========================================================
	-- Relative weights for the global job board roll.
	-- Non-integer weights are fine — the generator sums them for a float roll.
	-- With a 10-job pool: ~5 Starter, ~2.8 Mid, ~1.3 Premium, ~0.6 Prestige,
	-- ~0.2 Exclusive (1 per ~5 refreshes), ~0.07 Elite (1 per ~14 refreshes),
	-- ~0.03 Special (1 per ~33 refreshes = roughly once per 8–16 min).
	JobTierRarity = {
		Starter   = 50,
		Mid       = 28,
		Premium   = 13,
		Prestige  =  6,
		Exclusive =  2,
		Elite     =  0.7,
		Special   =  0.3,
	},

	-- =========================================================
	-- JOB GENERATOR DATA  (consumed by RadiantJobGenerator)
	-- Edit here to add damage types, flavor text, or rebalance tier rules.
	-- =========================================================

	-- Tier order from highest to lowest; controls rarity roll + furniture fallback.
	JobTierOrder = { "Special", "Elite", "Exclusive", "Prestige", "Premium", "Mid", "Starter" },

	-- Each entry maps a visible damage label to the minigame that fixes it.
	JobDamagePool = {
		{ label = "tack damage",   minigame = "TackRemoval"   },
		{ label = "loose staples", minigame = "StapleGunning" },
		{ label = "foam collapse", minigame = "FoamPadding"   },
		{ label = "torn seam",     minigame = "SeamStitching" },
	},

	-- One-line client flavor texts shown in the job details field.
	JobFlavorPool = {
		"Customer needs this done before the weekend.",
		"Handle with care — sentimental piece.",
		"Quick turnaround required.",
		"Client is very particular about fabric tension.",
		"This was my late mother's. Please be gentle.",
		"Going into a rental property — needs to hold up.",
		"Needs to match the existing set.",
		"Rush order. Tip possible.",
		"Condition is worse than the photos suggest.",
		"Client bought the fabric themselves.",
		"Second attempt — first upholsterer botched it.",
		"High-profile client. Discretion appreciated.",
	},

	-- Per-tier rules: how many furniture pieces, which categories, minigame chain length.
	-- pieces: ordered list of furniture categories drawn per piece slot.
	-- minigameCount: chain length for single-piece jobs only; ignored for multi-piece.
	JobTierConfig = {
		Starter   = { furnitureCount = {min=1, max=1}, pieces = {"Seating"},                    minigameCount = {min=1, max=1}, difficulty = "Easy",   fragile = false },
		Mid       = { furnitureCount = {min=1, max=2}, pieces = {"Seating", "Accent"},          minigameCount = {min=1, max=2}, difficulty = "Medium", fragile = false },
		Premium   = { furnitureCount = {min=2, max=2}, pieces = {"Seating", "Accent"},          minigameCount = {min=2, max=2}, difficulty = "Hard",   fragile = true  },
		Prestige  = { furnitureCount = {min=2, max=3}, pieces = {"Seating", "Accent", "Seating"}, minigameCount = {min=2, max=3}, difficulty = "Hard", fragile = true  },
		Exclusive = { furnitureCount = {min=2, max=3}, pieces = {"Seating", "Accent", "Accent"}, minigameCount = {min=2, max=3}, difficulty = "Hard",  fragile = true  },
		Elite     = { furnitureCount = {min=3, max=3}, pieces = {"Seating", "Accent", "Accent"}, minigameCount = {min=3, max=3}, difficulty = "Hard",  fragile = true  },
		Special   = { furnitureCount = {min=1, max=3}, pieces = {"Seating", "Accent", "Seating"}, minigameCount = {min=2, max=4}, difficulty = "Hard", fragile = true  },
	},

	-- Hand-crafted jobs for specific locations with built-in tagged models.
	-- Each entry generates a real job card on the board. locationOverride is mandatory.
	-- In Studio: add Repairable (bool, true) attribute to each Model in the slot template.
	--            Optionally add RepairOrder (number) to control interaction sequence.
	BespokeJobs = {
		-- {
		-- 	name             = "Supercar Seat Restoration",
		-- 	details          = "Client demands showroom-perfect leather on their prized possession.",
		-- 	tier             = "Prestige",
		-- 	pay              = 1500,
		-- 	followers        = 60,
		-- 	locationOverride = "SupercarGarage",
		-- 	minigames        = { "SeamStitching", "FoamPadding" },
		-- 	difficulty       = "Hard",
		-- 	fragile          = true,
		-- },
	},

	-- =========================================================
	-- TALKOGRAM
	-- =========================================================
	Talkogram = {
		commentMaxLength    = 80,
		commentsPerPlayer   = 3,
		popularLikeCount    = 5,
		bestPostIntervalSec = 2 * 60 * 60,
		tierTitles = {
			Perfect = "Absolutely nailed this %s. Client loved it.",
			Good    = "Pretty happy with how this %s turned out.",
			Pass    = "Just finished a %s — not my best, but done!",
		},
	},

	-- =========================================================
	-- CLIENT LOCATION SYSTEM
	-- =========================================================
	Locations = {
		fabricColors = {
			Color3.fromRGB(30,  50,  120),
			Color3.fromRGB(120, 30,  50),
			Color3.fromRGB(240, 230, 200),
			Color3.fromRGB(50,  90,  60),
			Color3.fromRGB(90,  90,  110),
			Color3.fromRGB(190, 155, 100),
			Color3.fromRGB(165, 110, 130),
			Color3.fromRGB(60,  60,  60),
			Color3.fromRGB(200, 180, 150),
			Color3.fromRGB(100, 140, 160),
		},
		frameColors = {
			Color3.fromRGB(180, 140, 90),
			Color3.fromRGB(80,  50,  30),
			Color3.fromRGB(30,  30,  30),
			Color3.fromRGB(240, 240, 235),
			Color3.fromRGB(140, 100, 60),
		},
		wallColors = {
			Color3.fromRGB(245, 245, 240),
			Color3.fromRGB(220, 210, 195),
			Color3.fromRGB(200, 215, 225),
			Color3.fromRGB(210, 225, 205),
			Color3.fromRGB(230, 220, 210),
		},
	},

	-- =========================================================
	-- REPUTATION  (0–5 float; tracks job performance for Talkogram)
	-- No longer gates job tiers — purely a player stat.
	-- =========================================================
	Reputation = {
		startValue = 0.0,
		maxValue   = 5.0,
		minValue   = 0.0,
		gain = {
			Perfect  =  0.20,
			Good     =  0.10,
			Pass     =  0.05,
		},
		-- Tier-scaled penalties per GDD §11.1
		failByTier = {
			Starter   = -0.03,
			Mid       = -0.05,
			Premium   = -0.10,
			Prestige  = -0.15,
			Exclusive = -0.22,
			Elite     = -0.30,
			Special   = -0.30,
		},
		abandonByTier = {
			Starter   = -0.05,
			Mid       = -0.08,
			Premium   = -0.15,
			Prestige  = -0.22,
			Exclusive = -0.32,
			Elite     = -0.45,
			Special   = -0.45,
		},
		-- Milestone rep thresholds for toolbox slot unlocks
		slotUnlockRep = { 0, 0, 0, 1.5, 3.0 }, -- slot N unlocks at this rep
		-- Tier range table for Direct Offers (GDD §3.2)
		directOfferRules = {
			{ minRep=1.0, maxRep=1.9, count=1, refreshSec=240, tiers={"Mid","Premium"} },
			{ minRep=2.0, maxRep=3.4, count=2, refreshSec=180, tiers={"Premium","Exclusive"} },
			{ minRep=3.5, maxRep=4.4, count=2, refreshSec=150, tiers={"Exclusive","Elite"} },
			{ minRep=4.5, maxRep=5.0, count=3, refreshSec=120, tiers={"Elite","Special"} },
		},
	},

	HotJobs = {
		intervalMin  = 300,   -- 5 minutes
		intervalMax  = 480,   -- 8 minutes
		countdownSec = 10,
		payMultiplier     = 3.0,
		followerBonus     = 0.75,
		tiers = { "Mid", "Premium", "Prestige" },  -- pool for hot job tier roll
	},

	DailyContracts = {
		-- Fixed pool; 3 random per day, seeded by date so all server players share
		pool = {
			{ id="complete_4_rare",   description="Complete 4 Premium+ jobs today",
			  goal={ kind="jobs", minTier="Premium", count=4 },
			  reward={ kind="usd", amount=500 } },
			{ id="perfect_2_fragile", description="Get Perfect on 2 Fragile jobs",
			  goal={ kind="perfects", fragileOnly=true, count=2 },
			  reward={ kind="perkCharge", perkId="curved_needle_bespoke", qty=1 } },
			{ id="earn_3000",         description="Earn $3,000 in a single session",
			  goal={ kind="earnUsd", amount=3000 },
			  reward={ kind="perkCharge", perkId="word_of_mouth_bespoke", qty=1 } },
			{ id="perfect_5_any",     description="Get Perfect on 5 jobs of any tier",
			  goal={ kind="perfects", count=5 },
			  reward={ kind="usd", amount=300 } },
			{ id="finish_10_jobs",    description="Complete any 10 jobs today",
			  goal={ kind="jobs", count=10 },
			  reward={ kind="usd", amount=400 } },
			{ id="three_minigame_chain", description="Complete a job with a 3+ minigame chain",
			  goal={ kind="minigameChain", minLength=3, count=1 },
			  reward={ kind="usd", amount=250 } },
		},
		dailyCount = 3,
	},

	-- =========================================================
	-- DIFFICULTY PRESETS
	-- Each entry is a partial override — only fields that differ from base
	-- GameConfig values are listed. Missing fields fall back to base.
	-- =========================================================
	DifficultyPresets = {
		Easy = {
			TackRemoval   = { tackCountMin=4,  tackCountMax=7,  approachTime=2.6,
			                  perfectMinProgress=0.65, goodMinProgress=0.35 },
			StapleGunning = { stapleCountMin=3, stapleCountMax=5, barSpeed=0.45,
			                  goodZoneWidth=0.15, perfectZoneWidth=0.07 },
			SeamStitching = { segmentCountMin=3, segmentCountMax=4,
			                  deviationTolerance=48, timePerSegment=12 },
			FoamPadding   = { pieceCount=3, timeLimit=65, perfectMinRatio=1.0, goodMinRatio=0.67 },
		},
		Medium = {
			-- no overrides; base GameConfig values apply
		},
		Hard = {
			TackRemoval   = { tackCountMin=12, tackCountMax=18, approachTime=1.4,
			                  perfectMinProgress=0.82, goodMinProgress=0.52 },
			StapleGunning = { stapleCountMin=9, stapleCountMax=14, barSpeed=0.85,
			                  goodZoneWidth=0.08, perfectZoneWidth=0.035,
			                  barSpeedRampUp=0.06 },
			SeamStitching = { segmentCountMin=8, segmentCountMax=12,
			                  deviationTolerance=20, timePerSegment=7 },
			FoamPadding   = { pieceCount=7, timeLimit=35, perfectMinRatio=1.0, goodMinRatio=0.80 },
		},
	},

	-- =========================================================
	-- PLAYER HOUSE SYSTEM  (GDD §9 — House Prestige)
	-- =========================================================
	PlayerHouses = {
		slotCount = 6,
		tierThresholds = { 0, 2000, 10000, 50000 },
		tierModelKeys  = { "StarterFlat", "CornerHouse", "WorkshopVilla", "SkylinePenthouse" },
	},
}
