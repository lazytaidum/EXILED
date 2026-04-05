local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteNames = require(ReplicatedStorage.Shared.Constants.RemoteNames)

local RemoteRegistry = {}
RemoteRegistry.Name = "RemoteRegistry"

function RemoteRegistry:Init()
	local sharedFolder = ReplicatedStorage:WaitForChild("Shared")
	local remotesFolder = sharedFolder:FindFirstChild("Remotes")
	if not remotesFolder then
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = sharedFolder
	end
	
	for _, remoteName in pairs(RemoteNames) do
		if not remotesFolder:FindFirstChild(remoteName) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = remoteName
			remote.Parent = remotesFolder
		end
	end
	
	self.RemotesFolder = remotesFolder
end

function RemoteRegistry:Start()
	print("[RemoteRegistry] Started")
end

function RemoteRegistry:GetRemote(name)
	return self.RemotesFolder:FindFirstChild(name)
end

return RemoteRegistry
