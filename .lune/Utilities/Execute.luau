--!optimize 2
--!strict

local Chalk = require("@packages/Chalk")
local Debug = require("@packages/Debug")
local GreenTea = require("@packages/GreenTea")
local GreenTeaUtilities = require("@packages/GreenTeaUtilities")
local LuauPolyfill = require("@packages/LuauPolyfill")
local process = require("@lune/process")

local Error = LuauPolyfill.Error
local console = LuauPolyfill.console

local COLOR_FORMATTERS: {[string]: (value: unknown) -> string} = {
	boolean = function(value: unknown): string
		return Chalk.Yellow(tostring(value))
	end;
	number = function(value: unknown): string
		return Chalk.Cyan(tostring(value))
	end;
	string = function(value: unknown): string
		return Chalk.Green(`"{value}"`)
	end;
}
setmetatable(COLOR_FORMATTERS, {
	__index = function(self, index: string): (value: unknown) -> string
		self[index] = tostring
		return tostring
	end;
})

export type AssertableResult = process.ExecResult & {
	Assert: (self: AssertableResult) -> AssertableResult,
}

local AssertableResult = {} :: AssertableResult;
(AssertableResult :: any).__index = AssertableResult

function AssertableResult:Assert()
	if not self.ok then
		console.warn(`Command failed:\n{self.stderr}\n{self.stdout}`)
		process.exit(self.code)
	end

	return self
end

(AssertableResult :: any).__tostring = function(self: AssertableResult): string
	local array = {`{Chalk.Magenta("AssertableResult<")}{Chalk.Gray("{")}`}
	local length = 1

	for key, value in Debug.AlphabeticalOrder(self) do
		length += 1
		array[length] = `\t{key} {Chalk.Gray("=")} {COLOR_FORMATTERS[typeof(value)](value)}{Chalk.Gray(",")}`
	end

	array[length + 1] = Chalk.Gray("}") .. Chalk.Magenta(">")

	return table.concat(array, "\n")
end

local isSpawnOptionsStdioKindRaw = GreenTeaUtilities.SmartLiteral("default", "inherit", "forward", "none")

local isStringArray = GreenTea.build(GreenTea.array(GreenTea.string()))
local isMaybeSpawnOptions = GreenTea.build(GreenTea.optional({
	cwd = GreenTea.optional(GreenTea.string());
	env = GreenTea.optional({[GreenTea.string()] = GreenTea.string()});
	shell = GreenTea.optional(GreenTea.union(GreenTea.boolean(), GreenTea.string()));
	stdio = GreenTea.optional(GreenTea.union(isSpawnOptionsStdioKindRaw, {
		stdout = GreenTea.optional(isSpawnOptionsStdioKindRaw);
		stderr = GreenTea.optional(isSpawnOptionsStdioKindRaw);
		stdin = GreenTea.optional(GreenTea.string());
	}));
	stdin = GreenTea.optional(GreenTea.string());
}))

local function Execute(command: {string}, options: process.ExecOptions?): AssertableResult
	do
		local typeSuccess0, typeError0 = isStringArray:matches(command)
		if not typeSuccess0 then
			local exception = Error.new(tostring(typeError0))
			exception.name = "TypeError"
			Error.captureStackTrace(exception, Execute)
			error(exception)
		end
		local typeSuccess1, typeError1 = isMaybeSpawnOptions:matches(options)
		if not typeSuccess1 then
			local exception = Error.new(tostring(typeError1))
			exception.name = "TypeError"
			Error.captureStackTrace(exception, Execute)
			error(exception)
		end
	end

	local binary = command[1]

	local arguments = table.clone(command)
	table.remove(arguments, 1)

	local spawnOptions: process.ExecOptions = if options then table.clone(options) else {}
	if spawnOptions.shell == false then
		spawnOptions.shell = nil
	elseif spawnOptions.shell == nil then
		spawnOptions.shell = true
	end

	local result = process.exec(binary, arguments, spawnOptions)
	return setmetatable(table.clone(result), AssertableResult) :: never
end

return Execute
