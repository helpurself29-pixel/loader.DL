local ClientSignals = {}

local listeners = {}

function ClientSignals.Connect(name, callback)
	local list = listeners[name]
	if not list then
		list = {}
		listeners[name] = list
	end
	table.insert(list, callback)
	return function()
		local index = table.find(list, callback)
		if index then
			table.remove(list, index)
		end
	end
end

function ClientSignals.Fire(name, ...)
	local list = listeners[name]
	if not list then
		return
	end
	for _, callback in table.clone(list) do
		task.spawn(callback, ...)
	end
end

return ClientSignals
