local Logging = require(script.Parent.Logging)

local function makeInstanceMap()
	local self = {
		fromIds = {},
		fromInstances = {},
	}

	function self:insert(id, instance)
		self.fromIds[id] = instance
		self.fromInstances[instance] = id
	end

	function self:removeId(id)
		local instance = self.fromIds[id]

		if instance ~= nil then
			self.fromIds[id] = nil
			self.fromInstances[instance] = nil
		else
			Logging.warn("Attempted to remove nonexistant ID %s", tostring(id))
		end
	end

	function self:removeInstance(instance)
		local id = self.fromInstances[instance]

		if id ~= nil then
			self.fromInstances[instance] = nil
			self.fromIds[id] = nil
		else
			Logging.warn("Attempted to remove nonexistant instance %s", tostring(instance))
		end
	end

	function self:destroyId(id)
		local instance = self.fromIds[id]
		self:removeId(id)

		if instance ~= nil then
			local descendantsToDestroy = {}

			for otherInstance in pairs(self.fromInstances) do
				if otherInstance:IsDescendantOf(instance) then
					table.insert(descendantsToDestroy, otherInstance)
				end
			end

			for _, otherInstance in ipairs(descendantsToDestroy) do
				self:removeInstance(otherInstance)
			end

			instance:Destroy()
		else
			Logging.warn("Attempted to destroy nonexistant ID %s", tostring(id))
		end
	end

	return self
end

local function setProperty(instance, key, value)
	-- The 'Contents' property of LocalizationTable isn't directly exposed, but
	-- has corresponding (deprecated) getters and setters.
	if key == "Contents" and instance.ClassName == "LocalizationTable" then
		instance:SetContents(value)
		return
	end

	-- If we don't have permissions to access this value at all, we can skip it.
	local readSuccess, existingValue = pcall(function()
		return instance[key]
	end)

	if not readSuccess then
		-- An error will be thrown if there was a permission issue or if the
		-- property doesn't exist. In the latter case, we should tell the user
		-- because it's probably their fault.
		if existingValue:find("lacking permission") then
			Logging.trace("Permission error reading property %s on class %s", tostring(key), instance.ClassName)
			return
		else
			error(("Invalid property %s on class %s: %s"):format(tostring(key), instance.ClassName, existingValue), 2)
		end
	end

	local writeSuccess, err = pcall(function()
		if existingValue ~= value then
			instance[key] = value
		end
	end)

	if not writeSuccess then
		error(("Cannot set property %s on class %s: %s"):format(tostring(key), instance.ClassName, err), 2)
	end

	return true
end

local Reconciler = {}
Reconciler.__index = Reconciler

function Reconciler.new()
	local self = {
		instanceMap = makeInstanceMap(),
	}

	return setmetatable(self, Reconciler)
end

function Reconciler:applyUpdate(requestedIds, virtualInstancesById)
	-- This function may eventually be asynchronous; it will require calls to
	-- the server to resolve instances that don't exist yet.
	local visitedIds = {}

	for _, id in ipairs(requestedIds) do
		self:__applyUpdatePiece(id, visitedIds, virtualInstancesById)
	end
end

--[[
	Update an existing instance, including its properties and children, to match
	the given information.
]]
function Reconciler:reconcile(virtualInstancesById, id, instance)
	local virtualInstance = virtualInstancesById[id]

	-- If an instance changes ClassName, we assume it's very different. That's
	-- not always the case!
	if virtualInstance.ClassName ~= instance.ClassName then
		-- TODO: Preserve existing children instead?
		local parent = instance.Parent
		self.instanceMap:destroyId(id)
		return self:__reify(virtualInstancesById, id, parent)
	end

	self.instanceMap:insert(id, instance)

	-- Some instances don't like being named, even if their name already matches
	setProperty(instance, "Name", virtualInstance.Name)

	for key, value in pairs(virtualInstance.Properties) do
		setProperty(instance, key, value.Value)
	end

	local existingChildren = instance:GetChildren()

	local unvisitedExistingChildren = {}
	for _, child in ipairs(existingChildren) do
		unvisitedExistingChildren[child] = true
	end

	for _, childId in ipairs(virtualInstance.Children) do
		local childData = virtualInstancesById[childId]

		local existingChildInstance
		for instance in pairs(unvisitedExistingChildren) do
			local ok, name, className = pcall(function()
				return instance.Name, instance.ClassName
			end)

			if ok then
				if name == childData.Name and className == childData.ClassName then
					existingChildInstance = instance
					break
				end
			end
		end

		if existingChildInstance ~= nil then
			unvisitedExistingChildren[existingChildInstance] = nil
			self:reconcile(virtualInstancesById, childId, existingChildInstance)
		else
			self:__reify(virtualInstancesById, childId, instance)
		end
	end

	if self:__shouldClearUnknownInstances(virtualInstance) then
		for existingChildInstance in pairs(unvisitedExistingChildren) do
			self.instanceMap:removeInstance(existingChildInstance)
			existingChildInstance:Destroy()
		end
	end

	-- The root instance of a project won't have a parent, like the DataModel,
	-- so we need to be careful here.
	if virtualInstance.Parent ~= nil then
		local parent = self.instanceMap.fromIds[virtualInstance.Parent]

		if parent == nil then
			Logging.info("Instance %s wanted parent of %s", tostring(id), tostring(virtualInstance.Parent))
			error("Rojo bug: During reconciliation, an instance referred to an instance ID as parent that does not exist.")
		end

		-- Some instances, like services, don't like having their Parent
		-- property poked, even if we're setting it to the same value.
		setProperty(instance, "Parent", parent)
		if instance.Parent ~= parent then
			instance.Parent = parent
		end
	end

	return instance
end

function Reconciler:__shouldClearUnknownInstances(virtualInstance)
	if virtualInstance.Metadata ~= nil then
		return not virtualInstance.Metadata.ignoreUnknownInstances
	else
		return true
	end
end

function Reconciler:__reify(virtualInstancesById, id, parent)
	local virtualInstance = virtualInstancesById[id]

	local instance = Instance.new(virtualInstance.ClassName)

	for key, value in pairs(virtualInstance.Properties) do
		-- TODO: Branch on value.Type
		setProperty(instance, key, value.Value)
	end

	instance.Name = virtualInstance.Name

	for _, childId in ipairs(virtualInstance.Children) do
		self:__reify(virtualInstancesById, childId, instance)
	end

	setProperty(instance, "Parent", parent)
	self.instanceMap:insert(id, instance)

	return instance
end

function Reconciler:__applyUpdatePiece(id, visitedIds, virtualInstancesById)
	if visitedIds[id] then
		return
	end

	visitedIds[id] = true

	local virtualInstance = virtualInstancesById[id]
	local instance = self.instanceMap.fromIds[id]

	-- The instance was deleted in this update
	if virtualInstance == nil then
		self.instanceMap:destroyId(id)
		return
	end

	-- An instance we know about was updated
	if instance ~= nil then
		self:reconcile(virtualInstancesById, id, instance)
		return instance
	end

	-- If the instance's parent already exists, we can stick it there
	local parentInstance = self.instanceMap.fromIds[virtualInstance.Parent]
	if parentInstance ~= nil then
		self:__reify(virtualInstancesById, id, parentInstance)
		return
	end

	-- Otherwise, we can check if this response payload contained the parent and
	-- work from there instead.
	local parentData = virtualInstancesById[virtualInstance.Parent]
	if parentData ~= nil then
		if visitedIds[virtualInstance.Parent] then
			error("Rojo bug: An instance was present and marked as visited but its instance was missing")
		end

		self:__applyUpdatePiece(virtualInstance.Parent, visitedIds, virtualInstancesById)
		return
	end

	Logging.trace("Instance ID %s, parent ID %s", tostring(id), tostring(virtualInstance.Parent))
	error("Rojo NYI: Instances with parents that weren't mentioned in an update payload")
end

return Reconciler