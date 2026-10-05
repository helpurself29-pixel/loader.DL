local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CombatConfig = require(script.Parent.CombatConfig)
local vfx = require(ReplicatedStorage:WaitForChild("ForgeVFX"))

vfx.init()

local VFXPlayer = {}

local templates = script.Parent:WaitForChild("VFX")

local effectsFolder = workspace:FindFirstChild("ActiveVFX")
if not effectsFolder then
	effectsFolder = Instance.new("Folder")
	effectsFolder.Name = "ActiveVFX"
	effectsFolder.Parent = workspace
end

local CLEANUP_FALLBACK = 15

local function place(effect, targetCFrame, reference)
	local moves = {}

	local function collect(instance)
		if instance:IsA("BasePart") then
			table.insert(moves, { instance, "CFrame", targetCFrame * reference:ToObjectSpace(instance.CFrame) })
		elseif instance:IsA("Attachment") and not instance.Parent:IsA("BasePart") and not instance.Parent:IsA("Attachment") then
			table.insert(moves, { instance, "CFrame", targetCFrame * reference:ToObjectSpace(instance.CFrame) })
		end
	end

	collect(effect)
	for _, descendant in effect:GetDescendants() do
		collect(descendant)
	end

	for _, move in moves do
		local instance = move[1]
		if instance:IsA("BasePart") then
			instance.Anchored = true
			instance.CanCollide = false
			instance.CanQuery = false
			instance.CanTouch = false
		end
		instance[move[2]] = move[3]
	end
end

function VFXPlayer.Emit(name, targetCFrame, onlyChild)
	local template = templates:FindFirstChild(name)
	local reference = CombatConfig.VFXReferences[name]
	if not template or not reference then
		warn("VFXPlayer: no effect or reference named", name)
		return
	end

	local effect = template:Clone()
	place(effect, targetCFrame, reference)
	effect.Parent = effectsFolder

	local target = effect
	if onlyChild then
		target = effect:FindFirstChild(onlyChild, true)
		if not target then
			effect:Destroy()
			return
		end
	end

	local cleaned = false
	local function cleanup()
		if not cleaned then
			cleaned = true
			effect:Destroy()
		end
	end

	local ok, env = pcall(vfx.emit, target)
	if ok and env and env.Finished then
		env.Finished:finally(cleanup)
	end
	task.delay(CLEANUP_FALLBACK, cleanup)
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
