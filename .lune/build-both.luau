--!optimize 2
--!strict
--[=[ lunar
	about = "Validates the existence of custom packages."
	args = "[-d,--destroy]"
]=]

local Execute = require("@utilities/Execute")
local LuauPolyfill = require("@packages/LuauPolyfill")
local PathFileSystem = require("@packages/PathFileSystem")
local RegEx = require("@lune/regex")
local process = require("@lune/process")
local task = require("@lune/task")

local Path = PathFileSystem.Path
local console = LuauPolyfill.console

local arguments = table.clone(process.args)
local DESTROY_MODE = (function()
	local index = table.find(arguments, "-d") or table.find(arguments, "--destroy")
	if index then
		table.remove(arguments, index)
		return true
	end
	return false
end)()

local ON_ARM64 = process.arch == "aarch64"
local ON_WINDOWS = process.os == "windows"
local TARGET_FOLDER = Path.new("target")
if ON_ARM64 then
	TARGET_FOLDER = TARGET_FOLDER:join(if ON_WINDOWS then "aarch64-pc-windows-msvc" else "aarch64-unknown-linux-gnu")
end

local RELEASE_FOLDER = TARGET_FOLDER:join("release")
local RELEASES_FOLDER = TARGET_FOLDER:join("releases")

local RELEASE_FILE = RELEASE_FOLDER:join(if ON_WINDOWS then "stylua.exe" else "stylua")

local FORMATTERS = Path.new("src"):join("formatters")
local TABLE_FILE = FORMATTERS:join("table.rs")
local ASSIGNMENT = FORMATTERS:join("assignment.rs")

local SEPARATOR_STRING = "const MULTI_LINE_SEPARATOR: &str = %q;"
local SEPARATOR_PATTERN = RegEx.new(string.format(SEPARATOR_STRING, "(;|,)"))

local EXPRESSIONS_STRING = "const MAX_EXPRESSIONS: usize = %*;"
local EXPRESSIONS_PATTERN = RegEx.new(string.format(EXPRESSIONS_STRING, "(\\d|usize::MAX)"))

local function BuildStyLua2(fileName: string, jobType: JobType)
	local command = {"cargo", "b", "--all-features", "--release", "-v"}
	--	if ON_ARM64 then
	--		table.insert(command, "--target")
	--		table.insert(command, if ON_WINDOWS then "aarch64-pc-windows-msvc" else "aarch64-unknown-linux-gnu")
	--	end
	Execute(command):Assert()

	if not PathFileSystem.IsFileSafe(RELEASE_FILE) then
		console.error("Release file not found?")
		process.exit(1)
	end

	if not PathFileSystem.IsDirectorySafe(RELEASES_FOLDER) then
		PathFileSystem.WriteDirectory(RELEASES_FOLDER)
	end

	PathFileSystem.Move(RELEASE_FILE, RELEASES_FOLDER:join(if ON_WINDOWS then `{fileName}.exe` else fileName), true)
end
local function GetTableInverse(fileSource: string, buildType: BuildType)
	return SEPARATOR_PATTERN:replace(
		fileSource,
		string.format(SEPARATOR_STRING, if buildType == "stylua2" then "," else ";")
	)
end
local function GetAssignmentInverse(fileSource: string, jobType: JobType)
	return EXPRESSIONS_PATTERN:replace(
		fileSource,
		string.format(EXPRESSIONS_STRING, if jobType == "dg" then "usize::MAX" else "1")
	)
end

if not PathFileSystem.IsFileSafe(TABLE_FILE) then
	console.warn("table.rs file not found")
	process.exit(1)
end
if not PathFileSystem.IsFileSafe(ASSIGNMENT) then
	console.warn("assignment.rs file not found")
	process.exit(1)
end

type BuildType = "stylua2" | "stylua2Roact"
type JobType = "hms" | "dg"

local function DetermineBuildType(): (BuildType, JobType, string, string)
	local tableFileSource = PathFileSystem.ReadFile(TABLE_FILE)
	local assignmentFileSource = PathFileSystem.ReadFile(ASSIGNMENT)

	if not SEPARATOR_PATTERN:isMatch(tableFileSource) then
		console.warn("Multi-line separator not found")
		process.exit(1)
	end
	local separatorCapture = SEPARATOR_PATTERN:captures(tableFileSource)
	if not separatorCapture then
		console.warn("Failed to capture multi-line separator?")
		process.exit(1)
		return "stylua2", "hms", "", ""
	end
	local separatorCaptureMatch = separatorCapture:get(1)
	if not separatorCaptureMatch then
		console.warn("Failed to capture multi-line separator type?")
		process.exit(1)
		return "stylua2", "hms", "", ""
	end

	if not EXPRESSIONS_PATTERN:isMatch(assignmentFileSource) then
		console.warn("Max expressions not found")
		process.exit(1)
	end
	local expressionsCapture = EXPRESSIONS_PATTERN:captures(assignmentFileSource)
	if not expressionsCapture then
		console.warn("Failed to capture max expressions?")
		process.exit(1)
		return "stylua2", "hms", "", ""
	end
	local expressionsCaptureMatch = expressionsCapture:get(1)
	if not expressionsCaptureMatch then
		console.warn("Failed to capture max expressions type?")
		process.exit(1)
		return "stylua2", "hms", "", ""
	end

	local captureType: ";" | "," = separatorCaptureMatch.text
	local expression: "1" | "usize::MAX" = expressionsCaptureMatch.text

	local buildType: BuildType = if captureType == ";" then "stylua2" else "stylua2Roact"
	local jobType: JobType = if expression == "usize::MAX" then "hms" else "dg"

	return buildType, jobType, tableFileSource, assignmentFileSource
end

local function Build(buildType: BuildType, jobType: JobType, tableFileSource: string, assignmentFileSource: string)
	print(`BuildStyLua2({buildType}, {jobType})`)
	-- BuildStyLua2(buildType, jobType)
	task.wait(2)
	PathFileSystem.WriteFile(TABLE_FILE, GetTableInverse(tableFileSource, buildType))

	print(`BuildStyLua2({if buildType == "stylua2" then "stylua2Roact" else "stylua2"}, {jobType})`)
	task.wait(2)
	-- BuildStyLua2(if buildType == "stylua2" then "stylua2Roact" else "stylua2", jobType)
end

local buildType: BuildType, jobType: JobType, tableFileSource, assignmentFileSource = DetermineBuildType()

Build(buildType, jobType, tableFileSource, assignmentFileSource)
PathFileSystem.WriteFile(ASSIGNMENT, GetAssignmentInverse(assignmentFileSource, jobType))
Build(buildType, if jobType == "dg" then "hms" else "dg", tableFileSource, assignmentFileSource)

PathFileSystem.WriteFile(TABLE_FILE, tableFileSource)
PathFileSystem.WriteFile(ASSIGNMENT, assignmentFileSource)

if DESTROY_MODE and PathFileSystem.IsDirectorySafe(RELEASE_FOLDER) then
	PathFileSystem.RemoveDirectory(RELEASE_FOLDER)
end
