-- src/shared/GrabConfig.luau

return {
	-- Input bindings
	GRAB_KEY        = Enum.KeyCode.E,
	THROW_KEY       = Enum.KeyCode.F,
	USE_MOUSE_THROW = true,

	-- Interaction range
	MAX_GRAB_DISTANCE     = 12,
	MAX_GRAB_DISTANCE_SVR = 20,
	MAX_OBJECT_MASS       = 5000,

	-- Carry position: hrp.Position + (0, CARRY_HEIGHT, 0) + mouseAimDir * CARRY_DISTANCE
	CARRY_DISTANCE  = 5,
	CARRY_HEIGHT    = 1.5,

	-- Carry velocity: speed = clamp(displacement * CARRY_SPEED, 0, MAX_CARRY_SPEED)
	CARRY_SPEED     = 20,
	MAX_CARRY_SPEED = 30,

	-- Throw velocity (studs/s). Applied client-side then re-applied server-side in the
	-- same tick as ownership transfer so there is no freeze gap.
	THROW_SPEED   = 40,
	THROW_UP_BIAS = 0.15,

	-- Anti-abuse
	GRAB_COOLDOWN    = 0.3,
	DISCONNECT_DELAY = 0.5,

	GRABBABLE_TAG = "Grabbable",
	GROUP_PLAYERS = "Players",
	GROUP_HELD    = "HeldObjects",
}
