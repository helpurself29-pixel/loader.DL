local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLookup = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("AnimationLookup"))

local CONFIG = {
	WalkSpeed = 16,
	SprintSpeed = 26,
	CrouchSpeed = 8,
	MoveThreshold = 0.75,
	FadeTime = 0.15,
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

local LOOPED = {
	Idle = { Priority = Enum.AnimationPriority.Idle, Looped = true },
	Walk = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.WalkSpeed },
	Run = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.SprintSpeed },
	Crouch = { Priority = Enum.AnimationPriority.Idle, Looped = true },
	["Crouch Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true, BaseSpeed = CONFIG.CrouchSpeed },
	Jump = { Priority = Enum.AnimationPriority.Movement, Looped = false },
}

local tracks = {}
for name, settings in LOOPED do
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
		track:Play(CONFIG.FadeTime)
	end
end

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Jumping then
		if current == "Jump" and tracks.Jump then
			tracks.Jump:Play(CONFIG.FadeTime)
		else
			switchTo("Jump")
		end
	end
end)

local connection
connection = RunService.Heartbeat:Connect(function()
	if not character.Parent or humanoid.Health <= 0 then
		connection:Disconnect()
		return
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		if current ~= "Jump" then
			switchTo("Jump")
		end
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local moving = speed > CONFIG.MoveThreshold and humanoid.MoveDirection.Magnitude > 0
	local crouching = character:GetAttribute("Crouching") == true

	local name
	if crouching then
		name = if moving then "Crouch Walk" else "Crouch"
	elseif moving then
		name = if speed > (CONFIG.WalkSpeed + CONFIG.SprintSpeed) / 2 then "Run" else "Walk"
	else
		name = "Idle"
	end
	switchTo(name)

	local settings = LOOPED[name]
	local track = tracks[name]
	if track and settings.BaseSpeed then
		track:AdjustSpeed(math.clamp(speed / settings.BaseSpeed, 0.5, 1.5))
	end
end)
