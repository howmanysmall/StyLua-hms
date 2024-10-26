--!optimize 2
--!strict

local LuauPolyfill = require("@packages/LuauPolyfill")
local process = require("@lune/process")

local console = LuauPolyfill.console

export type AssertableResult = process.SpawnResult & {
	Assert: (self: AssertableResult) -> AssertableResult,
}

local AssertableResult = {} :: AssertableResult;
(AssertableResult :: never).__index = AssertableResult

function AssertableResult:Assert()
	if not self.ok then
		console.warn(`Command failed:\n{self.stderr}\n{self.stdout}`)
		process.exit(self.code)
	end

	return self
end

local function Execute(command: { string }, options: process.SpawnOptions?): AssertableResult
	local binary = command[1]

	local arguments = table.clone(command)
	table.remove(arguments, 1)

	local spawnOptions: process.SpawnOptions = if options then table.clone(options) else {}
	if spawnOptions.shell == false then
		spawnOptions.shell = nil
	elseif spawnOptions.shell == nil then
		spawnOptions.shell = true
	end

	local result = process.spawn(binary, arguments, spawnOptions)
	return setmetatable(table.clone(result), AssertableResult) :: never
end

return Execute
