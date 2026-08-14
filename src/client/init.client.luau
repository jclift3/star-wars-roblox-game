--!strict
--[[
	Client entry point.

	Mirrors the server: controllers live in Controllers/ and the same two-phase
	loader runs them. Using one loader on both sides means the boot order rules
	are the same rules in both places, rather than two conventions to remember.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ServiceLoader = require(Shared.Core.ServiceLoader)

ServiceLoader.addFrom(script.Controllers)
ServiceLoader.start()
