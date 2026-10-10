local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local ClientSignals = require(Combat:WaitForChild("ClientSignals"))
local Theme = require(Combat:WaitForChild("Theme"))

local Colors = Theme.Colors
local Fonts = Theme.Fonts
local player = Players.LocalPlayer

local MOVES = {
	{ Name = "Push", Label = "PUSH", Config = CombatConfig.Push },
	{ Name = "Tackle", Label = "TACKLE", Config = CombatConfig.Tackle },
}

local GAMEPAD_GLYPHS = {
	[Enum.KeyCode.ButtonA] = "A",
	[Enum.KeyCode.ButtonB] = "B",
	[Enum.KeyCode.ButtonX] = "X",
	[Enum.KeyCode.ButtonY] = "Y",
	[Enum.KeyCode.ButtonL1] = "LB",
	[Enum.KeyCode.ButtonR1] = "RB",
	[Enum.KeyCode.ButtonL2] = "LT",
	[Enum.KeyCode.ButtonR2] = "RT",
}

local LOW_HEALTH = 0.3
local SPRINT_SPEED = (16 + 26) / 2

local function create(className, props, children)
	local instance = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	if props.Parent then
		instance.Parent = props.Parent
	end
	return instance
end

local function corner(radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius or Theme.CornerRadius) })
end

local function stroke(color, thickness, transparency)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function textStroke(transparency)
	return create("UIStroke", {
		Color = Colors.Ink,
		Thickness = 1,
		Transparency = transparency or 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

local function tween(instance, duration, goal, style, direction)
	local animation = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		goal
	)
	animation:Play()
	return animation
end

local function smooth(rate, dt)
	return 1 - math.exp(-rate * dt)
end

task.spawn(function()
	for _ = 1, 20 do
		if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Health, false) then
			return
		end
		task.wait(0.25)
	end
end)

local gui = create("ScreenGui", {
	Name = "HUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})

local scales = {}
local function scaled()
	local scale = create("UIScale", {})
	table.insert(scales, scale)
	return scale
end

local function rescale()
	local camera = workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else 1080
	local value = math.clamp(height / 1080, 0.65, 1.3)
	for _, scale in scales do
		scale.Scale = value
	end
end

local vignette = create("Frame", {
	Name = "Vignette",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 0,
	Parent = gui,
})

local vignetteFalloff = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.45, 0.62),
	NumberSequenceKeypoint.new(1, 1),
})

local edges = {}
for _, spec in {
	{ UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0), 90 },
	{ UDim2.fromScale(1, 0.34), UDim2.fromScale(0, 0.66), -90 },
	{ UDim2.fromScale(0.28, 1), UDim2.fromScale(0, 0), 0 },
	{ UDim2.fromScale(0.28, 1), UDim2.fromScale(0.72, 0), 180 },
} do
	table.insert(
		edges,
		create("Frame", {
			Size = spec[1],
			Position = spec[2],
			BackgroundColor3 = Colors.Ink,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = vignette,
		}, {
			create("UIGradient", { Rotation = spec[3], Transparency = vignetteFalloff }),
		})
	)
end

local crosshair = create("Frame", {
	Name = "Crosshair",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(64, 64),
	BackgroundTransparency = 1,
	Parent = gui,
}, { scaled() })

local dot = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(4, 4),
	BackgroundColor3 = Colors.Text,
	BorderSizePixel = 0,
	Parent = crosshair,
}, { corner(2), stroke(Colors.Ink, 1, 0.45) })

local crossLines = {}
for _, direction in { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) } do
	local horizontal = direction.Y == 0
	table.insert(crossLines, {
		Direction = direction,
		Frame = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = if horizontal then UDim2.fromOffset(7, 2) else UDim2.fromOffset(2, 7),
			BackgroundColor3 = Colors.Text,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Parent = crosshair,
		}, { stroke(Colors.Ink, 1, 0.6) }),
	})
end

local hitMarks = {}
for _, angle in { 45, 135, 225, 315 } do
	local radians = math.rad(angle)
	local markStroke = stroke(Colors.Ink, 1, 1)
	table.insert(hitMarks, {
		Direction = Vector2.new(math.cos(radians), math.sin(radians)),
		Stroke = markStroke,
		Frame = create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = angle,
			Size = UDim2.fromOffset(9, 2),
			BackgroundColor3 = Colors.Accent,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = crosshair,
		}, { markStroke }),
	})
end

local vitals = create("Frame", {
	Name = "Vitals",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 32, 1, -30),
	Size = UDim2.fromOffset(290, 44),
	BackgroundTransparency = 1,
	Parent = gui,
}, { scaled() })

create("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.new(0.6, 0, 0, 14),
	FontFace = Fonts.Display,
	Text = "VITALS",
	TextSize = 11,
	TextColor3 = Colors.TextMuted,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = vitals,
}, { textStroke(0.7) })

local healthValue = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -34, 0, -6),
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(80, 24),
	FontFace = Fonts.Mono,
	Text = "100",
	TextSize = 22,
	TextColor3 = Colors.Text,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = vitals,
}, { textStroke() })

local healthMax = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 1),
	BackgroundTransparency = 1,
	Size = UDim2.fromOffset(32, 14),
	FontFace = Fonts.Mono,
	Text = "/100",
	TextSize = 11,
	TextColor3 = Colors.TextMuted,
	TextXAlignment = Enum.TextXAlignment.Right,
	Parent = vitals,
}, { textStroke(0.7) })

local healthTrack = create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.fromScale(0, 1),
	Size = UDim2.new(1, 0, 0, 10),
	BackgroundColor3 = Colors.Panel,
	BackgroundTransparency = Theme.PanelTransparency,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Parent = vitals,
}, { corner(2), stroke(Colors.Line, 1, 0.1) })

local healthTrail = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Trail,
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	ZIndex = 1,
	Parent = healthTrack,
}, { corner(2) })

local healthFill = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Colors.Text,
	BorderSizePixel = 0,
	ZIndex = 2,
	Parent = healthTrack,
}, {
	corner(2),
	create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 186, 178)),
	}),
})

for _, fraction in { 0.25, 0.5, 0.75 } do
	create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(fraction, 0),
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = healthTrack,
	})
end

local abilityBar = create("Frame", {
	Name = "Abilities",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -30),
	Size = UDim2.fromOffset(0, 0),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundTransparency = 1,
	Parent = gui,
}, {
	scaled(),
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

local statusChip = create("Frame", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -124),
	Size = UDim2.fromOffset(104, 20),
	BackgroundColor3 = Colors.Panel,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Parent = gui,
}, { scaled(), corner(10) })
local statusStroke = stroke(Colors.Accent, 1, 1)
statusStroke.Parent = statusChip
local statusText = create("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	FontFace = Fonts.Display,
	Text = "CROUCHED",
	TextSize = 9,
	TextColor3 = Colors.Accent,
	TextTransparency = 1,
	Parent = statusChip,
})

local slots = {}
for index, move in MOVES do
	local slotScale = create("UIScale", {})
	local slotStroke = stroke(Colors.Line, 1, 0)
	local button = create("TextButton", {
		Name = move.Name,
		LayoutOrder = index,
		Size = UDim2.fromOffset(80, 80),
		BackgroundColor3 = Colors.Panel,
		BackgroundTransparency = Theme.PanelTransparency,
		AutoButtonColor = false,
		Text = "",
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = abilityBar,
	}, {
		slotScale,
		corner(),
		slotStroke,
		create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150)),
		}),
	})

	local accentLine = create("Frame", {
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundColor3 = Colors.Accent,
		BorderSizePixel = 0,
		ZIndex = 4,
		Parent = button,
	})

	local cooldownFill = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = button,
	})

	local nameLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		Size = UDim2.new(1, -8, 0, 12),
		BackgroundTransparency = 1,
		FontFace = Fonts.Display,
		Text = move.Label,
		TextSize = 9,
		TextColor3 = Colors.Text,
		ZIndex = 3,
		Parent = button,
	})

	local countdown = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromOffset(60, 26),
		BackgroundTransparency = 1,
		FontFace = Fonts.Mono,
		Text = "",
		TextSize = 22,
		TextColor3 = Colors.Text,
		ZIndex = 3,
		Parent = button,
	}, { textStroke() })

	local glyph = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromOffset(60, 30),
		BackgroundTransparency = 1,
		FontFace = Fonts.Label,
		Text = string.sub(move.Label, 1, 1),
		TextSize = 30,
		TextColor3 = Colors.Text,
		TextTransparency = 0.82,
		ZIndex = 1,
		Parent = button,
	})

	local keyChip = create("Frame", {
		Position = UDim2.fromOffset(6, 8),
		Size = UDim2.fromOffset(20, 20),
		BackgroundColor3 = Colors.Ink,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = button,
	}, { corner(3), stroke(Colors.LineBright, 1, 0.2) })

	local keyLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		FontFace = Fonts.Mono,
		Text = move.Config.Key.Name,
		TextSize = 11,
		TextColor3 = Colors.Text,
		ZIndex = 4,
		Parent = keyChip,
	})

	button.Activated:Connect(function()
		ClientSignals.Fire("Request", move.Name)
	end)
	button.MouseButton1Down:Connect(function()
		tween(slotScale, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		tween(slotScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	end)

	slots[move.Name] = {
		Move = move,
		Button = button,
		Scale = slotScale,
		Stroke = slotStroke,
		Accent = accentLine,
		Fill = cooldownFill,
		Name = nameLabel,
		Countdown = countdown,
		Glyph = glyph,
		KeyChip = keyChip,
		KeyLabel = keyLabel,
		ReadyAt = 0,
		Duration = 1,
		WasCooling = false,
	}
end

local function flashReady(slot)
	slot.Stroke.Color = Colors.Accent
	slot.Stroke.Transparency = 0
	slot.Accent.BackgroundTransparency = 0
	tween(slot.Stroke, 0.6, { Color = Colors.Line })
	slot.Scale.Scale = 1.08
	tween(slot.Scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

local function applyInputStyle()
	local inputType = UserInputService:GetLastInputType()
	local gamepad = string.find(inputType.Name, "Gamepad") ~= nil
	local touch = inputType == Enum.UserInputType.Touch or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)

	for _, slot in slots do
		local config = slot.Move.Config
		slot.KeyChip.Visible = not touch
		slot.KeyLabel.Text = if gamepad
			then (GAMEPAD_GLYPHS[config.GamepadButton] or config.GamepadButton.Name)
			else config.Key.Name
		slot.Button.Size = if touch then UDim2.fromOffset(92, 92) else UDim2.fromOffset(80, 80)
	end

	if touch then
		abilityBar.AnchorPoint = Vector2.new(1, 1)
		abilityBar.Position = UDim2.new(1, -170, 1, -36)
		statusChip.Position = UDim2.new(1, -230, 1, -146)
	else
		abilityBar.AnchorPoint = Vector2.new(0.5, 1)
		abilityBar.Position = UDim2.new(0.5, 0, 1, -30)
		statusChip.Position = UDim2.new(0.5, 0, 1, -124)
	end
end

local humanoid
local healthShown = 1
local trailShown = 1
local trailHold = 0
local lastHealth = 1
local hurtPulse = 0
local hitPulse = 0
local spread = 8
local crouchShown = false
local clock = 0

local function bindCharacter(character)
	humanoid = character:WaitForChild("Humanoid")
	local fraction = humanoid.Health / math.max(humanoid.MaxHealth, 1)
	healthShown, trailShown, lastHealth = fraction, fraction, fraction
	crouchShown = false

	humanoid.HealthChanged:Connect(function(health)
		local newFraction = math.clamp(health / math.max(humanoid.MaxHealth, 1), 0, 1)
		if newFraction < lastHealth - 0.001 then
			trailHold = 0.35
			hurtPulse = math.max(hurtPulse, math.clamp((lastHealth - newFraction) * 4, 0.35, 1))
			vitals.Position = UDim2.new(0, 36, 1, -30)
			tween(vitals, 0.3, { Position = UDim2.new(0, 32, 1, -30) }, Enum.EasingStyle.Elastic)
		elseif newFraction > lastHealth + 0.001 then
			healthFill.BackgroundColor3 = Colors.Heal
		end
		lastHealth = newFraction
	end)
end

ClientSignals.Connect("MoveUsed", function(moveName, cooldown)
	local slot = slots[moveName]
	if not slot then
		return
	end
	slot.ReadyAt = os.clock() + cooldown
	slot.Duration = math.max(cooldown, 0.01)
	slot.WasCooling = true
	slot.Scale.Scale = 0.9
	tween(slot.Scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
end)

ClientSignals.Connect("HitConfirm", function()
	hitPulse = 1
end)

ClientSignals.Connect("Hurt", function(strength)
	hurtPulse = math.max(hurtPulse, strength or 0.6)
end)

UserInputService.LastInputTypeChanged:Connect(applyInputStyle)
player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

local function watchViewport()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end
	rescale()
end
workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport)
watchViewport()
applyInputStyle()

local function updateCrosshair(dt, character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local speed, airborne = 0, false
	if root then
		local velocity = root.AssemblyLinearVelocity
		speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		airborne = math.abs(velocity.Y) > 4
	end

	crosshair.Visible = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		or not UserInputService.MouseEnabled

	local target = 7 + math.clamp(speed / 26, 0, 1.2) * 6 + (if airborne then 5 else 0) + hitPulse * 4
	spread += (target - spread) * smooth(14, dt)
	for _, line in crossLines do
		line.Frame.Position = UDim2.new(0.5, line.Direction.X * spread, 0.5, line.Direction.Y * spread)
	end

	hitPulse = math.max(hitPulse - dt * 4, 0)
	local hitDistance = 7 + (1 - hitPulse) * 6
	for _, mark in hitMarks do
		mark.Frame.Position = UDim2.new(0.5, mark.Direction.X * hitDistance, 0.5, mark.Direction.Y * hitDistance)
		mark.Frame.BackgroundTransparency = 1 - hitPulse
		mark.Stroke.Transparency = 1 - hitPulse * 0.5
	end
	dot.BackgroundColor3 = Colors.Text:Lerp(Colors.Accent, hitPulse)
end

local function updateHealth(dt)
	if not humanoid then
		return
	end
	local fraction = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)

	healthShown += (fraction - healthShown) * smooth(18, dt)
	if fraction >= trailShown then
		trailShown = healthShown
	elseif trailHold > 0 then
		trailHold -= dt
	else
		trailShown += (fraction - trailShown) * smooth(5, dt)
	end

	healthFill.Size = UDim2.fromScale(healthShown, 1)
	healthTrail.Size = UDim2.fromScale(trailShown, 1)
	healthValue.Text = tostring(math.ceil(humanoid.Health))
	healthMax.Text = "/" .. tostring(math.floor(humanoid.MaxHealth))

	local low = fraction <= LOW_HEALTH and fraction > 0
	local pulse = if low then (math.sin(clock * 6) + 1) / 2 else 0
	local baseColor = if low then Colors.Danger:Lerp(Colors.Text, pulse * 0.25) else Colors.Text
	healthFill.BackgroundColor3 = healthFill.BackgroundColor3:Lerp(baseColor, smooth(6, dt))
	healthValue.TextColor3 = if low then Colors.Danger else Colors.Text
	return low, pulse
end

local function updateVignette(dt, low, pulse, character)
	hurtPulse = math.max(hurtPulse - dt * 1.8, 0)
	local sprinting = false
	if character and humanoid then
		sprinting = humanoid.WalkSpeed > SPRINT_SPEED and humanoid.MoveDirection.Magnitude > 0
	end

	local danger = math.max(hurtPulse, if low then 0.45 + pulse * 0.3 else 0)
	local intensity = 0.16 + (if sprinting then 0.1 else 0) + danger * 0.55
	local color = Colors.Ink:Lerp(Colors.DangerDeep, math.clamp(danger * 1.4, 0, 1))
	for _, edge in edges do
		edge.BackgroundTransparency = 1 - math.clamp(intensity, 0, 0.85)
		edge.BackgroundColor3 = color
	end
end

local function updateSlots(character)
	local now = os.clock()
	local busy = character ~= nil and (character:GetAttribute("CombatBusy") or character:GetAttribute("Grabbed")) == true

	for _, slot in slots do
		local remaining = math.max(slot.ReadyAt - now, 0)
		local cooling = remaining > 0
		slot.Fill.Size = UDim2.fromScale(1, remaining / slot.Duration)
		slot.Countdown.Text = if cooling then string.format("%.1f", remaining) else ""
		slot.Glyph.Visible = not cooling
		slot.Accent.BackgroundTransparency = if cooling then 0.75 else (if busy then 0.5 else 0)
		slot.Name.TextTransparency = if busy or cooling then 0.45 else 0
		if slot.WasCooling and not cooling then
			slot.WasCooling = false
			flashReady(slot)
		end
	end
end

local function updateStatus(character)
	local crouching = character ~= nil and character:GetAttribute("Crouching") == true
	if crouching == crouchShown then
		return
	end
	crouchShown = crouching
	local visible = if crouching then 0 else 1
	tween(statusChip, 0.2, { BackgroundTransparency = if crouching then Theme.PanelTransparency else 1 })
	tween(statusStroke, 0.2, { Transparency = if crouching then 0.3 else 1 })
	tween(statusText, 0.2, { TextTransparency = visible })
end

RunService.RenderStepped:Connect(function(dt)
	clock += dt
	local character = player.Character
	updateCrosshair(dt, character)
	local low, pulse = updateHealth(dt)
	updateVignette(dt, low, pulse or 0, character)
	updateSlots(character)
	updateStatus(character)
end)
