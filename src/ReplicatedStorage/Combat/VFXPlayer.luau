local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(script.Parent.CombatConfig)

local VFXPlayer = {}

local templates = script.Parent:WaitForChild("VFX")

local effectsFolder = workspace:FindFirstChild("ActiveVFX")
if not effectsFolder then
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "ActiveVFX"
	effectsFolder.Parent = workspace
end

local function numbers(text)
	local list = {}
	for value in string.gmatch(text, "[^,%s]+") do
		table.insert(list, tonumber(value))
	end
	return list
end

local function parseValue(property, text)
	if property == "CFrame" then
		return CFrame.new(table.unpack(numbers(text)))
	elseif property == "Size" then
		return Vector3.new(table.unpack(numbers(text)))
	end
	return tonumber(text)
end

local function lerp(a, b, alpha)
	if type(a) == "number" then
		return a + (b - a) * alpha
	end
	return a:Lerp(b, alpha)
end

local function ease(style, direction, alpha)
	if style == "Constant" then
		return 0
	end
	local easingStyle = Enum.EasingStyle[style] or Enum.EasingStyle.Linear
	local easingDirection = Enum.EasingDirection[direction] or Enum.EasingDirection.Out
	return TweenService:GetValue(alpha, easingStyle, easingDirection)
end

local function sample(track, t)
	local first = track[1]
	if t <= first.Time then
		return first.Value
	end
	for i = 1, #track - 1 do
		local a, b = track[i], track[i + 1]
		if t < b.Time then
			local alpha = (t - a.Time) / math.max(b.Time - a.Time, 1e-4)
			return lerp(a.Value, b.Value, ease(a.Style, a.Direction, alpha))
		end
	end
	return track[#track].Value
end

local function prepare(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

local function playKeyframes(part, json)
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok then
		return 0
	end

	local tracks = {}
	local startTime, endTime = math.huge, 0
	for property, keyframes in data do
		local track = {}
		for _, keyframe in keyframes do
			table.insert(track, {
				Time = keyframe.Time,
				Value = parseValue(property, keyframe.Value),
				Style = keyframe.Style,
				Direction = keyframe.Direction,
			})
			if keyframe.Time > 0 then
				startTime = math.min(startTime, keyframe.Time)
			end
			endTime = math.max(endTime, keyframe.Time)
		end
		table.sort(track, function(a, b)
			return a.Time < b.Time
		end)
		if #track > 0 then
			tracks[property] = track
		end
	end
	if startTime == math.huge then
		startTime = 0
	end

	local base = part.CFrame
	local firstCFrame = tracks.CFrame and tracks.CFrame[1].Value

	local function apply(t)
		if tracks.Transparency then
			part.Transparency = sample(tracks.Transparency, t)
		end
		if tracks.Size then
			part.Size = sample(tracks.Size, t)
		end
		if firstCFrame then
			part.CFrame = base * firstCFrame:Inverse() * sample(tracks.CFrame, t)
		end
	end

	apply(startTime)
	local elapsed = 0
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local t = startTime + elapsed
		apply(t)
		if t >= endTime then
			connection:Disconnect()
			part:Destroy()
		end
	end)

	return endTime - startTime
end

local function tweenStartToEnd(model)
	local startPart = model:FindFirstChild("Start")
	local endPart = model:FindFirstChild("End")
	local duration = model:GetAttribute("EffectDuration")
	if typeof(duration) == "NumberRange" then
		duration = duration.Max
	end
	if not (startPart and endPart and type(duration) == "number" and duration > 0) then
		return 0
	end

	local delayTime = model:GetAttribute("EmitDelay") or 0
	local fromTransparency = model:GetAttribute("Part_Transparency_Start") or 0
	local toTransparency = model:GetAttribute("Part_Transparency_End") or 1
	local goal = {
		CFrame = endPart.CFrame,
		Size = endPart.Size,
		Transparency = toTransparency,
	}
	endPart:Destroy()

	task.delay(delayTime, function()
		if not startPart.Parent then
			return
		end
		startPart.Transparency = fromTransparency
		local tween = TweenService:Create(
			startPart,
			TweenInfo.new(duration, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
			goal
		)
		tween.Completed:Connect(function()
			startPart:Destroy()
		end)
		tween:Play()
	end)

	return delayTime + duration
end

local function groundColor(emitter)
	local attachment = emitter.Parent
	if not attachment:IsA("Attachment") then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { effectsFolder }
	local hit = workspace:Raycast(attachment.WorldPosition + Vector3.new(0, 2, 0), Vector3.new(0, -15, 0), params)
	if not hit or hit.Material.Name == emitter:GetAttribute("MaterialIgnore") then
		return
	end
	local color = if hit.Instance:IsA("Terrain")
		then workspace.Terrain:GetMaterialColor(hit.Material)
		else hit.Instance.Color
	emitter.Color = ColorSequence.new(color)
end

local function emitParticles(emitter)
	local delayTime = emitter:GetAttribute("EmitDelay") or 0
	local count = emitter:GetAttribute("EmitCount") or 1
	local duration = emitter:GetAttribute("EmitDuration") or 0
	if emitter:GetAttribute("UseGroundColor") then
		groundColor(emitter)
	end

	task.delay(delayTime, function()
		if not emitter.Parent then
			return
		end
		emitter:Emit(count)
		if duration > 0 then
			emitter.Enabled = true
			task.delay(duration, function()
				emitter.Enabled = false
			end)
		end
	end)

	return delayTime + duration + emitter.Lifetime.Max
end

local function showBeams(beam)
	if not beam:GetAttribute("Enabled") then
		return 0
	end
	beam.Enabled = true
	task.delay(0.3, function()
		beam.Enabled = false
	end)
	return 0.3
end

function VFXPlayer.Emit(name, targetCFrame)
	local template = templates:FindFirstChild(name)
	if not template then
		warn("VFXPlayer: no effect named", name)
		return
	end

	local effect = template:Clone()
	local reference = CombatConfig.VFXReference

	local parts = {}
	if effect:IsA("BasePart") then
		table.insert(parts, effect)
	end
	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	local placed = {}
	for _, part in parts do
		placed[part] = targetCFrame * reference:ToObjectSpace(part.CFrame)
	end
	for _, part in parts do
		prepare(part)
		part.CFrame = placed[part]
	end

	local holder
	for _, attachment in effect:GetDescendants() do
		if attachment:IsA("Attachment") and not attachment.Parent:IsA("BasePart") then
			if not holder then
				holder = Instance.new("Part")
				holder.Name = "AttachmentHolder"
				holder.Size = Vector3.one
				holder.Transparency = 1
				prepare(holder)
				holder.CFrame = targetCFrame * CFrame.new(0, 0, -3)
				holder.Parent = effect
			end
			attachment.CFrame = CFrame.identity
			attachment.Parent = holder
		end
	end

	effect.Parent = effectsFolder

	local lifetime = 0
	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			lifetime = math.max(lifetime, emitParticles(descendant))
		elseif descendant:IsA("Beam") then
			lifetime = math.max(lifetime, showBeams(descendant))
		elseif descendant:IsA("BasePart") and descendant:GetAttribute("MeshEmitter") then
			lifetime = math.max(lifetime, playKeyframes(descendant, descendant:GetAttribute("MeshEmitter")))
		end
	end
	for _, descendant in effect:GetDescendants() do
		if descendant:IsA("Model") and descendant:FindFirstChild("Start") then
			local start = descendant:FindFirstChild("Start")
			if not start:GetAttribute("MeshEmitter") then
				lifetime = math.max(lifetime, tweenStartToEnd(descendant))
			end
		end
	end

	task.delay(lifetime + 1, function()
		effect:Destroy()
	end)
end

function VFXPlayer.Flash(character, startTime, peakTime, endTime, peakTransparency)
	local template = templates:FindFirstChild("PushHighlight")
	if not template then
		return
	end
	task.delay(startTime, function()
		if not character.Parent then
			return
		end
		local highlight = template:Clone()
		highlight.Adornee = character
		highlight.FillTransparency = 1
		highlight.Enabled = true
		highlight.Parent = character

		local rise = TweenService:Create(highlight, TweenInfo.new(peakTime - startTime), {
			FillTransparency = peakTransparency,
		})
		local fall = TweenService:Create(highlight, TweenInfo.new(endTime - peakTime), {
			FillTransparency = 1,
		})
		rise.Completed:Connect(function()
			fall:Play()
		end)
		fall.Completed:Connect(function()
			highlight:Destroy()
		end)
		rise:Play()
	end)
end

return VFXPlayer
