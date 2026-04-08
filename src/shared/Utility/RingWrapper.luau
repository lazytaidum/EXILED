local RingWrapper = {}

local function attachDependencies(module, ring)
	local dependencies = rawget(module, "Dependencies")
	if type(dependencies) ~= "table" then
		return
	end

	for _, dependencyName in ipairs(dependencies) do
		module[dependencyName] = ring[dependencyName]
	end
end

function RingWrapper.CreateRing(modules)
	local ring = {}

	for _, module in ipairs(modules) do
		ring[module.Name] = module
	end

	return ring
end

function RingWrapper.Attach(modules, ring, legacyFieldName)
	for _, module in ipairs(modules) do
		module.Ring = ring

		if legacyFieldName then
			module[legacyFieldName] = ring
		end

		attachDependencies(module, ring)
	end
end

function RingWrapper.Boot(modules, legacyFieldName)
	local ring = RingWrapper.CreateRing(modules)
	RingWrapper.Attach(modules, ring, legacyFieldName)

	for _, module in ipairs(modules) do
		if module.Init then
			module:Init(ring)
		end
	end

	for _, module in ipairs(modules) do
		if module.Start then
			module:Start()
		end
	end

	return ring
end

return RingWrapper
