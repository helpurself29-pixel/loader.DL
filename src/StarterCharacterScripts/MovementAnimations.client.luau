local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLookup = require(ReplicatedStorage:WaitForChild("Combat"):WaitForChild("AnimationLookup"))

local CONFIG = {
	WalkSpeed = 16,
	SprintSpeed = 26,
	CrouchSpeed = 8,
	MoveThreshold = 0.75,

	GroundBlendRate = 12,
	AirBlendRate = 18,
	DirectionBlendRate = 8,
	RunBlendRate = 6,
	MinPlaybackRate = 0.6,
	MaxPlaybackRate = 1.5,
	PhaseCorrection = 0.08,

	JumpStartFade = 0.08,
	JumpToAirFade = 0.15,
	LandFadeIn = 0.08,
	LandFadeOut = 0.25,
	LandMovingWeight = 0.55,
	LandWeightRate = 10,
	LandLeadTime = 0.06,
	MinLandSpeed = 10,
	FallPoseDelay = 0.15,
	GroundOffset = 3,
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

local GROUND = { "Idle", "Walk", "Run", "Left Walk", "Right Walk", "Back Walk", "Crouch", "Crouch Walk" }
local CYCLE = { "Walk", "Run", "Left Walk", "Right Walk", "Back Walk" }

local SETTINGS = {
	Idle = { Priority = Enum.AnimationPriority.Idle, Looped = true },
	Walk = { Priority = Enum.AnimationPriority.Movement, Looped = true },
	Run = { Priority = Enum.AnimationPriority.Movement, Looped = true },
	["Left Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true },
	["Right Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true },
	["Back Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true },
	Crouch = { Priority = Enum.AnimationPriority.Idle, Looped = true },
	["Crouch Walk"] = { Priority = Enum.AnimationPriority.Movement, Looped = true },
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

local weights = {}
local appliedWeights = {}
for _, name in GROUND do
	weights[name] = if name == "Idle" then 1 else 0
	local track = tracks[name]
	if track then
		track:Play(0, math.max(weights[name], 0.001), 1)
		appliedWeights[name] = weights[name]
	end
end

local direction = { Forward = 1, Back = 0, Left = 0, Right = 0 }
local runAlpha = 0
local appliedSpeeds = {}

local airPhase
local airTimer = 0
local fallSpeed = 0
local landedEarly = false
local landingTrack

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances = { character }
rayParams.IgnoreWater = true

local function smooth(rate, dt)
	return 1 - math.exp(-rate * dt)
end

local function setWeight(name, weight)
	local track = tracks[name]
	if track and math.abs((appliedWeights[name] or -1) - weight) > 0.01 then
		appliedWeights[name] = weight
		track:AdjustWeight(math.max(weight, 0.001), 0)
	end
end

local function setSpeed(name, speed)
	local track = tracks[name]
	if track and math.abs((appliedSpeeds[name] or -1) - speed) > 0.02 then
		appliedSpeeds[name] = speed
		track:AdjustSpeed(speed)
	end
end

local function stopAir(fade)
	if tracks.JumpStart and tracks.JumpStart.IsPlaying then
		tracks.JumpStart:Stop(fade)
	end
	if tracks.Jump and tracks.Jump.IsPlaying then
		tracks.Jump:Stop(fade)
	end
	airPhase = nil
end

local function land()
	stopAir(CONFIG.LandFadeIn)
	if fallSpeed < CONFIG.MinLandSpeed then
		fallSpeed = 0
		return
	end
	local name = if fallSpeed >= CONFIG.BigFallSpeed then "Big Fall Landing" else "Jump Landing"
	local track = tracks[name] or tracks["Jump Landing"]
	if landingTrack and landingTrack ~= track then
		landingTrack:Stop(CONFIG.LandFadeIn)
	end
	landingTrack = track
	if track then
		track:Play(CONFIG.LandFadeIn, 1, 1)
	end
	fallSpeed = 0
end

local function startAir(phase)
	if landingTrack then
		landingTrack:Stop(CONFIG.JumpStartFade)
		landingTrack = nil
	end
	if phase == "start" and tracks.JumpStart then
		if tracks.Jump and tracks.Jump.IsPlaying then
			tracks.Jump:Stop(CONFIG.JumpStartFade)
		end
		tracks.JumpStart:Play(CONFIG.JumpStartFade, 1, 1)
		airPhase = "start"
	else
		if tracks.Jump then
			tracks.Jump:Play(CONFIG.JumpToAirFade, 1, 1)
		end
		airPhase = "air"
	end
end

humanoid.StateChanged:Connect(function(_, new)
	if new == Enum.HumanoidStateType.Jumping then
		fallSpeed = 0
		landedEarly = false
		startAir("start")
	elseif new == Enum.HumanoidStateType.Freefall then
		landedEarly = false
		if not airPhase then
			airPhase = "pending"
			airTimer = 0
		end
	elseif new == Enum.HumanoidStateType.Landed then
		if not landedEarly then
			land()
		end
		landedEarly = false
	end
end)

local function updateAir(velocity, dt)
	fallSpeed = math.max(fallSpeed, -velocity.Y)

	if airPhase == "pending" then
		airTimer += dt
		if airTimer >= CONFIG.FallPoseDelay then
			startAir("air")
		end
	end

	if airPhase == "start" then
		local start = tracks.JumpStart
		if not start or not start.IsPlaying or start.TimePosition >= start.Length - CONFIG.JumpToAirFade then
			if start then
				start:Stop(CONFIG.JumpToAirFade)
			end
			if tracks.Jump then
				tracks.Jump:Play(CONFIG.JumpToAirFade, 1, 1)
			end
			airPhase = "air"
		end
	end

	local jump = tracks.Jump
	if airPhase == "air" and jump and jump.IsPlaying and jump.Length > 0 and jump.TimePosition >= jump.Length - 0.05 then
		jump:AdjustSpeed(0)
	end

	if velocity.Y < 0 and not landedEarly then
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -(CONFIG.GroundOffset + 10), 0), rayParams)
		if hit then
			local distance = root.Position.Y - hit.Position.Y - CONFIG.GroundOffset
			if distance <= -velocity.Y * CONFIG.LandLeadTime then
				landedEarly = true
				land()
			end
		end
	end
end

local function updateDirection(velocity, speed, dt)
	if speed < CONFIG.MoveThreshold then
		return
	end
	local localVelocity = root.CFrame:VectorToObjectSpace(Vector3.new(velocity.X, 0, velocity.Z))
	local forward, right = -localVelocity.Z, localVelocity.X
	local total = math.abs(forward) + math.abs(right)
	local target = {
		Forward = math.max(forward, 0) / total,
		Back = math.max(-forward, 0) / total,
		Right = math.max(right, 0) / total,
		Left = math.max(-right, 0) / total,
	}
	local alpha = smooth(CONFIG.DirectionBlendRate, dt)
	for key, value in target do
		direction[key] += (value - direction[key]) * alpha
	end
end

local function groundTargets(speed, moving, crouching, dt)
	local targets = {}
	if crouching then
		local move = if moving then math.clamp(speed / CONFIG.CrouchSpeed, 0, 1) else 0
		targets.Crouch = 1 - move
		targets["Crouch Walk"] = move
		return targets
	end

	local move = if moving then math.clamp(speed / CONFIG.WalkSpeed, 0, 1) else 0
	local runTarget = math.clamp((speed - CONFIG.WalkSpeed) / (CONFIG.SprintSpeed - CONFIG.WalkSpeed), 0, 1)
	runAlpha += (runTarget - runAlpha) * smooth(CONFIG.RunBlendRate, dt)

	targets.Idle = 1 - move
	targets.Walk = move * direction.Forward * (1 - runAlpha)
	targets.Run = move * direction.Forward * runAlpha
	targets["Back Walk"] = move * direction.Back
	targets["Left Walk"] = move * direction.Left
	targets["Right Walk"] = move * direction.Right

	for _, name in { "Run", "Back Walk", "Left Walk", "Right Walk" } do
		if not tracks[name] and targets[name] > 0 then
			targets.Walk += targets[name]
			targets[name] = 0
		end
	end
	return targets
end

local function syncCycle(speed)
	local walk, run = tracks.Walk, tracks.Run
	local walkLength = if walk and walk.Length > 0 then walk.Length else 0.833
	local runLength = if run and run.Length > 0 then run.Length else walkLength
	local cycleLength = walkLength + (runLength - walkLength) * runAlpha
	local baseSpeed = CONFIG.WalkSpeed + (CONFIG.SprintSpeed - CONFIG.WalkSpeed) * runAlpha
	local rate = math.clamp(speed / baseSpeed, CONFIG.MinPlaybackRate, CONFIG.MaxPlaybackRate)

	local leader, leaderWeight = nil, -1
	for _, name in CYCLE do
		if tracks[name] and weights[name] > leaderWeight then
			leader, leaderWeight = name, weights[name]
		end
	end
	if not leader then
		return
	end
	local leaderTrack = tracks[leader]
	local phase = if leaderTrack.Length > 0 then leaderTrack.TimePosition / leaderTrack.Length else 0

	for _, name in CYCLE do
		local track = tracks[name]
		if track and track.Length > 0 then
			setSpeed(name, rate * track.Length / cycleLength)
			if name ~= leader and weights[name] > 0.01 then
				local trackPhase = track.TimePosition / track.Length
				local drift = math.abs(trackPhase - phase)
				if math.min(drift, 1 - drift) > CONFIG.PhaseCorrection then
					track.TimePosition = phase * track.Length
				end
			end
		end
	end

	if tracks["Crouch Walk"] then
		setSpeed("Crouch Walk", math.clamp(speed / CONFIG.CrouchSpeed, CONFIG.MinPlaybackRate, CONFIG.MaxPlaybackRate))
	end
end

local function updateLanding(moving, dt)
	if not landingTrack then
		return
	end
	if not landingTrack.IsPlaying then
		landingTrack = nil
		return
	end
	local target = if moving then CONFIG.LandMovingWeight else 1
	local current = landingTrack.WeightTarget
	landingTrack:AdjustWeight(current + (target - current) * smooth(CONFIG.LandWeightRate, dt), 0)
	if landingTrack.Length > 0 and landingTrack.TimePosition >= landingTrack.Length - CONFIG.LandFadeOut then
		landingTrack:Stop(CONFIG.LandFadeOut)
		landingTrack = nil
	end
end

local connection
connection = RunService.Heartbeat:Connect(function(dt)
	if not character.Parent or humanoid.Health <= 0 then
		connection:Disconnect()
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local state = humanoid:GetState()
	local inAir = state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall
	local moving = speed > CONFIG.MoveThreshold and humanoid.MoveDirection.Magnitude > 0
	local crouching = character:GetAttribute("Crouching") == true

	if inAir then
		updateAir(velocity, dt)
	elseif airPhase then
		if airPhase ~= "pending" and not landedEarly then
			land()
		else
			stopAir(CONFIG.LandFadeIn)
		end
	end

	local airborne = inAir and airPhase ~= "pending" and not landedEarly
	local targets = {}
	if not airborne then
		updateDirection(velocity, speed, dt)
		targets = groundTargets(speed, moving, crouching, dt)
	end

	local alpha = smooth(if airborne then CONFIG.AirBlendRate else CONFIG.GroundBlendRate, dt)
	for _, name in GROUND do
		weights[name] += ((targets[name] or 0) - weights[name]) * alpha
		setWeight(name, weights[name])
	end

	syncCycle(speed)
	updateLanding(moving, dt)
end)
