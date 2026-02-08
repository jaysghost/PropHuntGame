local MeleeConstants = {
	-- Tags
	HITBOX_EXCLUDE_TAG = "HitboxExclude",

	-- Attributes
	WEAPON_TYPE_ATTRIBUTE = "weaponType",
	DAMAGE_ATTRIBUTE = "damage",
	RANGE_ATTRIBUTE = "range",
	HITBOX_SIZE_ATTRIBUTE = "hitboxSize",
	HITBOX_OFFSET_ATTRIBUTE = "hitboxOffset",
	ATTACK_RATE_ATTRIBUTE = "attackRate",
	VIEW_MODEL_ATTRIBUTE = "viewModel",

	-- Attack types
	ATTACK_TYPE = {
		PRIMARY = 1,
		SECONDARY = 2,
	},

	-- Input
	KEYBOARD_ATTACK_KEY_CODE = Enum.UserInputType.MouseButton1,
	KEYBOARD_ATTACK2_KEY_CODE = Enum.UserInputType.MouseButton2,
	GAMEPAD_ATTACK_KEY_CODE = Enum.KeyCode.ButtonR1,
	GAMEPAD_ATTACK2_KEY_CODE = Enum.KeyCode.ButtonR2,

	-- Visualization
	SWING_TRAIL_DURATION = 0.3,
	SWING_TRAIL_TRANSPARENCY = 0.2,
	SWING_TRAIL_COLOR = Color3.fromRGB(255, 255, 255),
	SWING_TRAIL_WIDTH = 0.1,

	-- Hit effects
	HIT_SOUND_DELAY = 0.05,

	-- View model
	VIEW_MODEL_BIND_NAME = "MeleeViewModel",
	VIEW_MODEL_OFFSET = CFrame.new(0.5, 0, -0.3),

	-- View model bobbing
	VIEW_MODEL_BOBBING_SPEED = 0.4,
	VIEW_MODEL_BOBBING_AMOUNT = 0.05,
	VIEW_MODEL_BOBBING_TRANSITION_SPEED = 10,

	-- Hit detection
	HITBOX_VISUALIZATION = false,  -- Set to true for debugging
	HITBOX_COLOR = Color3.fromRGB(255, 0, 0),
	HITBOX_TRANSPARENCY = 0.8,

	-- Default hitbox values (used when attributes aren't set)
	DEFAULT_HITBOX_SIZE = Vector3.new(4, 2, 5),  -- Increased from original
	DEFAULT_HITBOX_OFFSET = Vector3.new(0, 0, -2.5),

	-- Animation names
	ANIMATION_NAMES = {
		EQUIP = "Equip",
		IDLE = "Idle",
		ATTACK1 = "Attack1",
		ATTACK2 = "Attack2",
	},

	-- Cooldown
	ATTACK_COOLDOWN = 0.1,  -- Minimum time between attacks

	-- Hit tracking
	HIT_DEBOUNCE_TIME = 0.2,  -- Time before same target can be hit again
}

return MeleeConstants