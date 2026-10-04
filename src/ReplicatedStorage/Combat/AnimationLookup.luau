local RunService = game:GetService("RunService")

local Combat = script.Parent

local NAMES = {
	Push = "Push",
	TackleAttempt = "Tackle Attemptt",
	Tackler = "Tackler",
	Tackled = "Tackled",
}

local LIST_NAME = "PublishedAnimationIds"

local AnimationLookup = {}

local function isBlank(id)
	return id == nil or id == "" or id == "rbxassetid://0"
end

if RunService:IsServer() then
	local source = game:GetService("ServerStorage"):WaitForChild("Animations")

	local list = Combat:FindFirstChild(LIST_NAME)
	if not list then
		list = Instance.new("Folder")
		list.Name = LIST_NAME
		list.Parent = Combat
	end

	local function publish(animation)
		local value = list:FindFirstChild(animation.Name)
		if not value then
			value = Instance.new("StringValue")
			value.Name = animation.Name
			value.Parent = list
		end
		value.Value = animation.AnimationId
	end

	local function track(instance)
		if instance:IsA("Animation") then
			publish(instance)
			instance:GetPropertyChangedSignal("AnimationId"):Connect(function()
				publish(instance)
			end)
		end
	end

	for _, descendant in source:GetDescendants() do
		track(descendant)
	end
	source.DescendantAdded:Connect(track)

	function AnimationLookup.Get(key)
		local name = NAMES[key] or key
		for _, descendant in source:GetDescendants() do
			if descendant:IsA("Animation") and descendant.Name == name then
				if isBlank(descendant.AnimationId) then
					return nil, `ServerStorage.Animations has no ID set for "{name}" yet`
				end
				return descendant
			end
		end
		return nil, `No Animation named "{name}" in ServerStorage.Animations`
	end
else
	local list = Combat:WaitForChild(LIST_NAME)

	function AnimationLookup.Get(key)
		local name = NAMES[key] or key
		local value = list:WaitForChild(name, 5)
		if not value then
			return nil, `No Animation named "{name}" in ServerStorage.Animations`
		end
		if isBlank(value.Value) then
			return nil, `ServerStorage.Animations has no ID set for "{name}" yet`
		end
		local animation = Instance.new("Animation")
		animation.Name = name
		animation.AnimationId = value.Value
		return animation
	end
end

return AnimationLookup
