local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLookup = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("AnimationLookup"))

local CONFIG = {
	WalkSpeed = 16,
	SprintSpeed = 26,
	CrouchSpeed = 8,
	MoveThreshold = 0.75,
	FadeTime = 0.15,
	BigFallSpeed = 75,
}

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

if humanoid.RigType ~= Enum.HumanoidRigType.R6 then
	warn("MovementAnimations: these animations are R6 but this character is R15. Set Avatar Settings > Avatar Type to R6.")
	return
end

local defaultAnimate = character:WaitForChild("Animate", 5)
if defaultAnimate then
	defaultAnimate:Destroy()
end
for _, playing in animator:GetPlayingAnimationTracks() do
	playing:Stop(0)
end

local SETTINGS = {
	Idle = { Priority = Enum.AnimationPriority.Idle, Looped = true },
	Walk = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.WalkSpeed },
	["Left Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.WalkSpeed },
	["Right Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.WalkSpeed },
	["Back Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.WalkSpeed },
	Run = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.SprintSpeed },
	Crouch = { Priority = Enum.AnimationPriority.Idle, Looped = true },
	["Crouch Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.CrouchSpeed },
	JumpStart = { Priority = Enum.AnimationPriority.Movement, Looped = false },
	Jump = { Priority = Enum.AnimationPriority.Movement, Looped = false },
	["Jump Landing"] = { Priority = Enum.AnimationPriority.Action, Looped = false },
	["Big Fall Landing"] = { Priority = Enum.AnimationPriority.Action, Looped = false },
}

local tracks = {}
for name, settings in SETTINGS do
	local animation, problem = AnimationLookup.Get(name)
	if animation then
		local track = animator:LoadAnimation(animation)
		track.Priority = settings.Priority
		track.Looped = settings.Looped
		tracks[name] = track
	else
		warn(problem)
	end
end

local current
local fallSpeed = 0

local function switchTo(name)
	if current == name then
		return
	end
	if current and tracks[current] then
		tracks[current]:Stop(CONFIG.FadeTime)
	end
	current = name
	local track = tracks[name]
	if track then
		track:Play(CONFIG.FadeTime, 1, 1)
	end
end

local function playLanding()
	local name = if fallSpeed >= CONFIG.BigFallSpeed then "Big Fall Landing" else "Jump Landing"
	local track = tracks[name] or tracks["Jump Landing"]
	if track then
		track:Play(0.05, 1, 1)
	end
end

local function pickMovement(velocity, speed)
	local localVelocity = root.CFrame:VectorToObjectSpace(Vector3.new(velocity.X, 0, velocity.Z))
	local forward, right = -localVelocity.Z, localVelocity.X

	local name
	if math.abs(right) > math.abs(forward) then
		name = if right > 0 then "Right Walk" else "Left Walk"
	elseif forward < 0 then
		name = "Back Walk"
	else
		name = if speed > (CONFIG.WalkSpeed + CONFIG.SprintSpeed) / 2 then "Run" else "Walk"
	end

	if not tracks[name] then
		name = "Walk"
	end
	return name
end

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Jumping then
		fallSpeed = 0
		if tracks.JumpStart then
			if current == "JumpStart" then
				tracks.JumpStart:Play(0.05, 1, 1)
			else
				switchTo("JumpStart")
			end
		else
			switchTo("Jump")
		end
	elseif new == Enum.HumanoidStateType.Freefall then
		if current ~= "JumpStart" then
			switchTo("Jump")
		end
	elseif new == Enum.HumanoidStateType.Landed then
		playLanding()
		fallSpeed = 0
	end
end)

local connection
connection = RunService.Heartbeat:Connect(function()
	if not character.Parent or humanoid.Health <= 0 then
		connection:Disconnect()
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local state = humanoid:GetState()

	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		fallSpeed = math.max(fallSpeed, -velocity.Y)
		if current == "JumpStart" then
			local track = tracks.JumpStart
			if not track or not track.IsPlaying then
				switchTo("Jump")
			end
		elseif current ~= "Jump" then
			switchTo("Jump")
		end
		local jumpTrack = tracks.Jump
		if current == "Jump" and jumpTrack and jumpTrack.Length > 0 and jumpTrack.TimePosition >= jumpTrack.Length - 0.05 then
			jumpTrack:AdjustSpeed(0)
		end
		return
	end

	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = speed > CONFIG.MoveThreshold and humanoid.MoveDirection.Magnitude > 0
	local crouching = character:GetAttribute("Crouching") == true

	local name
	if crouching then
		name = if moving then "Crouch Walk" else "Crouch"
	elseif moving then
		name = pickMovement(velocity, speed)
	else
		name = "Idle"
	end
	switchTo(name)

	local settings = SETTINGS[name]
	local track = tracks[name]
	if track and settings.BaseSpeed then
		track:AdjustSpeed(math.clamp(speed / settings.BaseSpeed, 0.5, 1.5))
	end
end)
