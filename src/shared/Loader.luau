--!strict
-- Loader: small dependency-injection helper.
-- Requires every ModuleScript child of a folder and returns a name -> module map,
-- then can init/start those modules in a defined dependency order.

local Loader = {}

export type LifecycleModule = {
	init: ((deps: any) -> ())?,
	start: (() -> ())?,
	[any]: any,
}

-- Require all ModuleScript children of a container, returning a name -> module map.
function Loader.requireChildren(container: Instance): { [string]: any }
	local modules: { [string]: any } = {}
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") then
			modules[child.Name] = require(child :: ModuleScript)
			print(("[Loader] loaded %s"):format(child.Name))
		end
	end
	return modules
end

-- Produce a name list ordered by `order` first (only names that exist),
-- then any remaining modules in arbitrary order.
local function orderedNames(modules: { [string]: any }, order: { string }?): { string }
	local names: { string } = {}
	local seen: { [string]: boolean } = {}

	if order then
		for _, name in order do
			if modules[name] ~= nil then
				table.insert(names, name)
				seen[name] = true
			end
		end
	end

	for name in modules do
		if not seen[name] then
			table.insert(names, name)
		end
	end

	return names
end

-- Call module.init(deps) on each module that defines it, in dependency order.
function Loader.initModules(modules: { [string]: any }, deps: any, order: { string }?)
	for _, name in orderedNames(modules, order) do
		local module = modules[name]
		if type(module) == "table" and type(module.init) == "function" then
			module.init(deps)
			print(("[Loader] init %s"):format(name))
		end
	end
end

-- Call module.start() on each module that defines it, in dependency order.
function Loader.startModules(modules: { [string]: any }, order: { string }?)
	for _, name in orderedNames(modules, order) do
		local module = modules[name]
		if type(module) == "table" and type(module.start) == "function" then
			module.start()
			print(("[Loader] start %s"):format(name))
		end
	end
end

return Loader
