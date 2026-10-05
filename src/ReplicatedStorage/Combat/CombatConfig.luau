local FPS = 60

return {
	VFXReferences = {
		Push = CFrame.new(-61.768433, 3, 40.589294),
		Tackle = CFrame.new(-61.768433, 3, 40.589294),
		["Walk-Run-Jump"] = CFrame.new(-76.380249, 3.10867, 40.514404),
		["Jump-Land"] = CFrame.new(-85.258057, 3.126669, 40.542301),
	},

	MovementVFX = {
		MaxDistance = 150,
		MinAirTime = 0.2,
		JumpUpSpeed = 8,
		MinStepSpeed = 10,
		StepMinRange = 0.25,
		GroundCheckDistance = 3.6,
	},

	Push = {
		Key = Enum.KeyCode.E,
		GamepadButton = Enum.KeyCode.ButtonX,
		Cooldown = 1.2,
		HitTime = 23 / FPS,
		HighlightStart = 9 / FPS,
		HighlightPeak = 21 / FPS,
		HighlightEnd = 30 / FPS,
		HighlightPeakTransparency = 0.3,
		HitboxSize = Vector3.new(5, 6, 5),
		HitboxOffset = CFrame.new(0, 0, -3),
		KnockbackForward = 60,
		KnockbackUp = 20,
		KnockbackTime = 0.2,
	},

	Tackle = {
		Key = Enum.KeyCode.R,
		GamepadButton = Enum.KeyCode.ButtonY,
		Cooldown = 4,
		DashSpeed = 45,
		DashTime = 0.45,
		HitWindow = 0.5,
		VFXTime = 22 / FPS,
		HitboxSize = Vector3.new(4, 6, 4),
		HitboxOffset = CFrame.new(0, 0, -2.5),
		TacklerLength = 1.571,
		TackledLength = 2.152,
		AttemptLength = 1.81,
	},
}
