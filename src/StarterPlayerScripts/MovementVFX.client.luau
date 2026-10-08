local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local VFXPlayer = require(Combat:WaitForChild("VFXPlayer"))

local CONFIG = CombatConfig.MovementVFX

local FEET = {
	{ Leg = "Left Leg", Attachment = "Step1" },
	{ Leg = "Right Leg", Attachment = "Step2" },
}

local states = setmetatable({}, { __mode = "k" })

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function newState()
	local feet = {}
	for i in FEET do
		feet[i] = { Min = math.huge, Max = -math.huge, Armed = false }
	end
	return { InAir = false, AirTime = 0, FallSpeed = 0, Feet = feet }
end

local function isGrounded(root)
	return workspace:Raycast(root.Position, Vector3.new(0, -CONFIG.GroundCheckDistance, 0), rayParams) ~= nil
end

local function updateFeet(character, root, state, dt)
	for i, foot in FEET do
		local leg = character:FindFirstChild(foot.Leg)
		if leg then
			local tracker = state.Feet[i]
			local height = leg.CFrame:PointToWorldSpace(Vector3.new(0, -leg.Size.Y / 2, 0)).Y - root.Position.Y

			tracker.Min = math.min(height, tracker.Min + 0.5 * dt)
			tracker.Max = math.max(height, tracker.Max - 0.5 * dt)

			local range = tracker.Max - tracker.Min
			if range >= CONFIG.StepMinRange then
				if tracker.Armed and height <= tracker.Min + range * 0.2 then
					tracker.Armed = false
					VFXPlayer.Emit("Walk-Run-Jump", root.CFrame, foot.Attachment)
				elseif height >= tracker.Min + range * 0.5 then
					tracker.Armed = true
				end
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local characters = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(characters, player.Character)
		end
	end
	local active = workspace:FindFirstChild("ActiveVFX")
	if active then
		table.insert(characters, active)
	end
	rayParams.FilterDescendantsInstances = characters

	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart")

		if not humanoid or not root or humanoid.Health <= 0 then
			continue
		end
		if (root.Position - camera.CFrame.Position).Magnitude > CONFIG.MaxDistance then
			states[character] = nil
			continue
		end

		local state = states[character]
		if not state then
			state = newState()
			states[character] = state
		end

		local velocity = root.AssemblyLinearVelocity
		if isGrounded(root) then
			if state.InAir and state.AirTime >= CONFIG.MinAirTime and state.FallSpeed >= CONFIG.LandVFXMinFallSpeed then
				VFXPlayer.Emit("Jump-Land", root.CFrame)
			end
			state.InAir = false
			state.AirTime = 0
			state.FallSpeed = 0

			local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
			if speed >= CONFIG.MinStepSpeed then
				updateFeet(character, root, state, dt)
			end
		else
			if not state.InAir and velocity.Y > CONFIG.JumpUpSpeed then
				VFXPlayer.Emit("Walk-Run-Jump", root.CFrame)
			end
			state.InAir = true
			state.AirTime += dt
			state.FallSpeed = math.max(state.FallSpeed, -velocity.Y)
		end
	end
end)
