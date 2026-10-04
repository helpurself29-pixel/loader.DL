local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Remote = Combat:WaitForChild("CombatRemote")
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local AnimationLookup = require(Combat:WaitForChild("AnimationLookup"))
local VFXPlayer = require(Combat:WaitForChild("VFXPlayer"))

local player = Players.LocalPlayer

local tracks = {}
local lastUsed = {}
local dash
local warned = {}

local function getParts()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return character, humanoid, root
	end
	return nil
end

local function getTrack(name)
	local character, humanoid = getParts()
	if not character then
		return nil
	end
	local cached = tracks[name]
	if cached and cached.Parent == character then
		return cached.Track
	end

	local animation, problem = AnimationLookup.Get(name)
	if not animation then
		if not warned[name] then
			warned[name] = true
			warn(problem)
		end
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	tracks[name] = { Track = track, Parent = character }
	return track
end

local function play(name)
	local track = getTrack(name)
	if track then
		track:Play(0.05)
	end
end

local function stop(name)
	local cached = tracks[name]
	if cached then
		cached.Track:Stop(0.05)
	end
end

local function stopDash()
	if dash then
		dash:Destroy()
		dash = nil
	end
end

local function applyVelocity(root, velocity, duration)
	local attachment = root:FindFirstChild("RootAttachment") or Instance.new("Attachment", root)
	local force = Instance.new("LinearVelocity")
	force.Attachment0 = attachment
	force.MaxForce = math.huge
	force.VectorVelocity = velocity
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.Parent = root
	task.delay(duration, function()
		force:Destroy()
	end)
	return force
end

local function ready(move, cooldown)
	local character, _, root = getParts()
	if not character or root.Anchored then
		return false
	end
	if character:GetAttribute("CombatBusy") or character:GetAttribute("Grabbed") then
		return false
	end
	local now = os.clock()
	if lastUsed[move] and now - lastUsed[move] < cooldown then
		return false
	end
	lastUsed[move] = now
	return true
end

local function onPush(_, state)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if ready("Push", CombatConfig.Push.Cooldown) then
		play("Push")
		Remote:FireServer("Push")
	end
	return Enum.ContextActionResult.Sink
end

local function onTackle(_, state)
	if state ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if ready("Tackle", CombatConfig.Tackle.Cooldown) then
		local _, _, root = getParts()
		local config = CombatConfig.Tackle
		local direction = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		play("TackleAttempt")
		stopDash()
		dash = applyVelocity(root, direction * config.DashSpeed, config.DashTime)
		Remote:FireServer("Tackle")
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("Push", onPush, true, CombatConfig.Push.Key, CombatConfig.Push.GamepadButton)
ContextActionService:BindAction("Tackle", onTackle, true, CombatConfig.Tackle.Key, CombatConfig.Tackle.GamepadButton)
ContextActionService:SetTitle("Push", "Push")
ContextActionService:SetTitle("Tackle", "Tackle")

player.CharacterAdded:Connect(function()
	tracks = {}
	dash = nil
end)

Remote.OnClientEvent:Connect(function(action, ...)
	if action == "Play" then
		play(...)
	elseif action == "TackleHit" then
		stopDash()
		stop("TackleAttempt")
		play("Tackler")
	elseif action == "Knockback" then
		local velocity, duration = ...
		local _, _, root = getParts()
		if root then
			applyVelocity(root, velocity, duration)
		end
	elseif action == "Effect" then
		local name, character = ...
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		if name == "Push" then
			local config = CombatConfig.Push
			VFXPlayer.Flash(
				character,
				config.HighlightStart,
				config.HighlightPeak,
				config.HighlightEnd,
				config.HighlightPeakTransparency
			)
			task.delay(config.HitTime, function()
				if root.Parent then
					VFXPlayer.Emit("Push", root.CFrame)
				end
			end)
		elseif name == "Tackle" then
			task.delay(CombatConfig.Tackle.VFXTime, function()
				if root.Parent then
					VFXPlayer.Emit("Tackle", root.CFrame)
				end
			end)
		end
	end
end)
