local FPS = 60

return {
	VFXReference = CFrame.new(-61.768433, 3, 40.589294),

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
