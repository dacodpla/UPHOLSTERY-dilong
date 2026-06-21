--[[
	ShopData / Perk Catalog
	ModuleScript — ReplicatedStorage.Shared.Data.ShopData
	Single source of truth for both the shop UI and the PerkSystem effect lookup.

	Per-perk schema:
		id            : string  - unique key
		name          : string  - display name
		grade         : "Bolt" | "Bespoke"
		category      : "MinigameTool" | "Economic" | "Follower" | "Reputation"
		              | "Protection" | "Board" | "Wildcard"
		minigame      : string? - only for MinigameTool category
		price         : number  - cost per single charge
		description   : string
		effect        : table   - merged into MinigameRunner params or post-job calc
		condition     : table?  - e.g. { minResult = "Good" } for Bespoke perks
		requiresRep   : number? - rep threshold to purchase
		requiresTier  : string? - post-launch tier gate (Premium+)
]]

local ShopData = {}

ShopData.All = {}

local function add(perk)
	ShopData.All[perk.id] = perk
end

-- ── MINIGAME TOOLS ─────────────────────────────────────────────────────────

add({
	id="tack_magnet_bolt", name="Tack Magnet", grade="Bolt", category="MinigameTool",
	minigame="TackRemoval", price=250,
	description="Approach time +0.5s",
	effect={ approachTimeBonus=0.5 },
})
add({
	id="tack_magnet_bespoke", name="Tack Magnet", grade="Bespoke", category="MinigameTool",
	minigame="TackRemoval", price=750, requiresRep=1.5,
	description="Approach time +1.0s AND tack spawn gap wider",
	effect={ approachTimeBonus=1.0, tackSpawnGapBonus=0.5 },
})
add({
	id="sharp_eye_bolt", name="Sharp Eye", grade="Bolt", category="MinigameTool",
	minigame="TackRemoval", price=300,
	description="Tack count -2",
	effect={ tackCountReduction=2 },
})

add({
	id="staple_guide_bolt", name="Staple Guide", grade="Bolt", category="MinigameTool",
	minigame="StapleGunning", price=300,
	description="Zone widths +20%",
	effect={ zoneWidthMultiplier=1.20 },
})
add({
	id="staple_guide_bespoke", name="Staple Guide", grade="Bespoke", category="MinigameTool",
	minigame="StapleGunning", price=900, requiresRep=2.0,
	description="Zone widths +35% AND no ramp-up",
	effect={ zoneWidthMultiplier=1.35, disableRampUp=true },
})
add({
	id="grip_wrap_bolt", name="Grip Wrap", grade="Bolt", category="MinigameTool",
	minigame="StapleGunning", price=350,
	description="Bar speed -0.10",
	effect={ barSpeedReduction=0.10 },
})

add({
	id="curved_needle_bolt", name="Curved Needle", grade="Bolt", category="MinigameTool",
	minigame="SeamStitching", price=250,
	description="Deviation tolerance +8",
	effect={ deviationToleranceBonus=8 },
})
add({
	id="curved_needle_bespoke", name="Curved Needle", grade="Bespoke", category="MinigameTool",
	minigame="SeamStitching", price=750, requiresRep=1.5,
	description="Deviation tolerance +16 AND auto-snaps to path start",
	effect={ deviationToleranceBonus=16, autoSnapToStart=true },
})

add({
	id="foam_press_kit_bolt", name="Foam Press Kit", grade="Bolt", category="MinigameTool",
	minigame="FoamPadding", price=350,
	description="Piece count -1, time +8s",
	effect={ pieceCountReduction=1, timeLimitBonus=8 },
})
add({
	id="foam_press_kit_bespoke", name="Foam Press Kit", grade="Bespoke", category="MinigameTool",
	minigame="FoamPadding", price=1000, requiresRep=2.0,
	description="Piece count -2, time +15s",
	effect={ pieceCountReduction=2, timeLimitBonus=15 },
})

-- ── ECONOMIC ───────────────────────────────────────────────────────────────

add({
	id="premium_invoice_bolt", name="Premium Invoice", grade="Bolt", category="Economic",
	price=400,
	description="+5% pay on any completion",
	effect={ payMultiplier=0.05 },
})
add({
	id="premium_invoice_bespoke", name="Premium Invoice", grade="Bespoke", category="Economic",
	price=1100, requiresRep=2.0,
	description="+12% pay on Good or better",
	effect={ payMultiplier=0.12 }, condition={ minResult="Good" },
})
add({
	id="rush_surcharge_bolt", name="Rush Surcharge", grade="Bolt", category="Economic",
	price=500,
	description="+8% pay if done before 75% time (currently +8% flat)",
	effect={ payMultiplier=0.08 },
})

-- ── FOLLOWER ───────────────────────────────────────────────────────────────

add({
	id="portfolio_shot_bolt", name="Portfolio Shot", grade="Bolt", category="Follower",
	price=350,
	description="+10% followers on completion",
	effect={ followerMultiplier=0.10 },
})
add({
	id="portfolio_shot_bespoke", name="Portfolio Shot", grade="Bespoke", category="Follower",
	price=900, requiresRep=2.0,
	description="+25% followers on completion",
	effect={ followerMultiplier=0.25 },
})
add({
	id="word_of_mouth_bolt", name="Word of Mouth", grade="Bolt", category="Follower",
	price=450,
	description="+8% followers on Good or better",
	effect={ followerMultiplier=0.08 }, condition={ minResult="Good" },
})
add({
	id="word_of_mouth_bespoke", name="Word of Mouth", grade="Bespoke", category="Follower",
	price=1300, requiresRep=2.5,
	description="+20% followers on Good or better AND next Direct Offer refreshes",
	effect={ followerMultiplier=0.20, refreshDirectOffer=true }, condition={ minResult="Good" },
})

-- ── REPUTATION ─────────────────────────────────────────────────────────────

add({
	id="thank_you_card_bolt", name="Thank You Card", grade="Bolt", category="Reputation",
	price=400,
	description="+0.03 rep on any completion",
	effect={ repBonus=0.03 },
})
add({
	id="thank_you_card_bespoke", name="Thank You Card", grade="Bespoke", category="Reputation",
	price=1100, requiresRep=1.5,
	description="+0.08 rep on Perfect only",
	effect={ repBonus=0.08 }, condition={ minResult="Perfect" },
})

-- ── PROTECTION ─────────────────────────────────────────────────────────────

add({
	id="safety_net_bolt", name="Safety Net", grade="Bolt", category="Protection",
	price=500,
	description="Fail rep penalty -25%",
	effect={ failPenaltyMultiplier=0.75 },
})
add({
	id="safety_net_bespoke", name="Safety Net", grade="Bespoke", category="Protection",
	price=1400, requiresRep=2.5,
	description="Fail rep penalty -45% AND abandon penalty -20%",
	effect={ failPenaltyMultiplier=0.55, abandonPenaltyMultiplier=0.80 },
})
add({
	id="fragile_specialist_bolt", name="Fragile Specialist", grade="Bolt", category="Protection",
	price=600,
	description="Fragile multiplier 0.6 -> 0.72",
	effect={ fragileMultiplierOverride=0.72 },
})
add({
	id="fragile_specialist_bespoke", name="Fragile Specialist", grade="Bespoke", category="Protection",
	price=1600, requiresRep=3.0,
	description="Fragile multiplier 0.6 -> 0.82",
	effect={ fragileMultiplierOverride=0.82 },
})

-- ── WILDCARD ───────────────────────────────────────────────────────────────

add({
	id="second_wind_bolt", name="Second Wind", grade="Bolt", category="Wildcard",
	price=450,
	description="After fail, next job's rep loss halved",
	effect={ nextJobRepLossMultiplier=0.5 },
})

-- ── HELPERS ────────────────────────────────────────────────────────────────

function ShopData.GetById(id)
	return ShopData.All[id]
end

function ShopData.GetByCategory(category)
	local out = {}
	for _, p in pairs(ShopData.All) do
		if p.category == category then table.insert(out, p) end
	end
	table.sort(out, function(a, b)
		if a.name ~= b.name then return a.name < b.name end
		return a.grade < b.grade
	end)
	return out
end

function ShopData.GetCategories()
	return { "MinigameTool", "Economic", "Follower", "Reputation", "Protection", "Wildcard" }
end

return ShopData
