local function hex(value)
	return Color3.fromHex(value)
end

local function family(fontEnum, weight)
	return Font.new(Font.fromEnum(fontEnum).Family, weight)
end

return {
	Colors = {
		Ink = hex("07080A"),
		Panel = hex("101317"),
		PanelRaised = hex("171B21"),
		Line = hex("2B323B"),
		LineBright = hex("4A5562"),
		Text = hex("ECE6D8"),
		TextMuted = hex("8C939C"),
		Accent = hex("FFB23F"),
		AccentDeep = hex("C7741A"),
		Danger = hex("FF4B3E"),
		DangerDeep = hex("8E1C14"),
		Heal = hex("7CE3A4"),
		Trail = hex("F4EBDD"),
	},

	Fonts = {
		Display = Font.fromEnum(Enum.Font.Michroma),
		Label = family(Enum.Font.Sarpanch, Enum.FontWeight.SemiBold),
		Mono = family(Enum.Font.RobotoMono, Enum.FontWeight.Bold),
	},

	PanelTransparency = 0.18,
	CornerRadius = 4,
	ShakeScale = 1,
	ReducedMotion = false,
}
