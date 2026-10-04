local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Combat = ReplicatedStorage:WaitForChild("Combat")
local Remote = Combat:WaitForChild("CombatRemote")
local CombatConfig = require(Combat:WaitForChild("CombatConfig"))
local AnimationLookup = require(Combat:WaitForChild("AnimationLookup"))

local lastUsed = {}

local function getParts(character)
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and humanoid.Health > 0 then
		return humanoid, root
	end
	return nil
end

local function isFree(character)
	return not character:GetAttribute("CombatBusy") and not character:GetAttribute("Grabbed")
end

local function onCooldown(player, move, cooldown)
	lastUsed[player] = lastUsed[player] or {}
	local now = os.clock()
	if lastUsed[player][move] and now - lastUsed[player][move] < cooldown * 0.9 then
		return true
	end
	lastUsed[player][move] = now
	return false
end

local function findTargets(attacker, root, size, offset)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attacker }

	local targets = {}
	for _, part in workspace:GetPartBoundsInBox(root.CFrame * offset, size, params) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not targets[model] and getParts(model) then
			targets[model] = true
		end
	end
	return targets
end

local function playOnNpc(character, animationName)
	local animation = AnimationLookup.Get(animationName)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator or not animation then
		return
	end
	local track = animator:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
end

local function playAnimation(character, animationName)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		Remote:FireClient(player, "Play", animationName)
	else
		playOnNpc(character, animationName)
	end
end

local function knockback(character, velocity, duration)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		Remote:FireClient(player, "Knockback", velocity, duration)
		return
	end
	local _, root = getParts(character)
	if not root then
		return
	end
	if root:CanSetNetworkOwnership() then
		root:SetNetworkOwner(nil)
	end
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
end

local function push(player, character, root)
	local config = CombatConfig.Push
	character:SetAttribute("CombatBusy", true)
	Remote:FireAllClients("Effect", "Push", character)

	task.delay(config.HitTime, function()
		local _, currentRoot = getParts(character)
		if currentRoot then
			local velocity = currentRoot.CFrame.LookVector * config.KnockbackForward
				+ Vector3.new(0, config.KnockbackUp, 0)
			for target in findTargets(character, currentRoot, config.HitboxSize, config.HitboxOffset) do
				if not target:GetAttribute("Grabbed") then
					knockback(target, velocity, config.KnockbackTime)
				end
			end
		end
		character:SetAttribute("CombatBusy", nil)
	end)
end

local function landTackle(player, character, root, target)
	local config = CombatConfig.Tackle
	local _, targetRoot = getParts(target)
	if not targetRoot then
		return
	end

	target:SetAttribute("Grabbed", true)
	root.Anchored = true
	targetRoot.Anchored = true
	targetRoot.CFrame = root.CFrame

	Remote:FireClient(player, "TackleHit")
	playAnimation(target, "Tackled")
	Remote:FireAllClients("Effect", "Tackle", character)

	task.delay(config.TacklerLength, function()
		if root.Parent then
			root.Anchored = false
		end
		character:SetAttribute("CombatBusy", nil)
	end)
	task.delay(config.TackledLength, function()
		if targetRoot.Parent then
			targetRoot.Anchored = false
		end
		target:SetAttribute("Grabbed", nil)
	end)
end

local function tackle(player, character, root)
	local config = CombatConfig.Tackle
	character:SetAttribute("CombatBusy", true)

	local started = os.clock()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local humanoid = getParts(character)
		if not humanoid then
			connection:Disconnect()
			character:SetAttribute("CombatBusy", nil)
			return
		end
		for target in findTargets(character, root, config.HitboxSize, config.HitboxOffset) do
			if isFree(target) then
				connection:Disconnect()
				landTackle(player, character, root, target)
				return
			end
		end
		if os.clock() - started > config.HitWindow then
			connection:Disconnect()
			task.delay(math.max(config.AttemptLength - config.HitWindow, 0), function()
				character:SetAttribute("CombatBusy", nil)
			end)
		end
	end)
end

Remote.OnServerEvent:Connect(function(player, action)
	local character = player.Character
	local humanoid, root = getParts(character)
	if not humanoid or not isFree(character) or root.Anchored then
		return
	end

	if action == "Push" then
		if not onCooldown(player, "Push", CombatConfig.Push.Cooldown) then
			push(player, character, root)
		end
	elseif action == "Tackle" then
		if not onCooldown(player, "Tackle", CombatConfig.Tackle.Cooldown) then
			tackle(player, character, root)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	lastUsed[player] = nil
end)
