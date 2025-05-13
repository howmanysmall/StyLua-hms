--!optimize 2
--!strict
--[=[ lunar
	about = "Validates the existence of custom packages."
	args = "[-h] [--arch <arch>] [--os <os>] [-d] [-v]"
]=]

local ArgParse = require("@packages/ArgParse")
local Execute = require("@utilities/Execute")
local LuauPolyfill = require("@packages/LuauPolyfill")
local PathFileSystem = require("@packages/PathFileSystem")
local RegEx = require("@lune/regex")
local process = require("@lune/process")

local Path = PathFileSystem.Path
local console = LuauPolyfill.console

type Architecture = process.Arch
type OS = process.OS
type Path = PathFileSystem.Path

local ARCHITECTURES: {Architecture} = {"aarch64", "x86_64"}
local OPERATING_SYSTEMS: {OS} = {"linux", "macos", "windows"}

local parser = ArgParse("build", "Build both types of stylua2.")
parser:option("--arch", `CPU architecture: {table.concat(ARCHITECTURES, ", ")}`, process.arch, nil, 1)
parser:option("--os", `Target OS: {table.concat(OPERATING_SYSTEMS, ", ")}`, process.os, nil, 1)
parser:flag("-d --destroy", "Whether or not to destroy the release directory.")
parser:flag("-v --verbose", "Enable verbose output")

local function ToKey(architecture: Architecture, operatingSystem: OS): string
	return if architecture == process.arch and operatingSystem == process.os
		then "default"
		else `{architecture}-{operatingSystem}`
end

type Metadata = {
	GetPath: (target: Path) -> Path,
	Target: string?,
}
local function AsMetadata(getPath: (target: Path) -> Path, target: string?): Metadata
	return table.freeze({
		GetPath = getPath;
		Target = target;
	})
end

local ArchitectureMetadata: {[string]: Metadata} = {
	default = AsMetadata(function(target: Path): Path
		return target:join("release")
	end);

	[ToKey("aarch64", "windows")] = AsMetadata(function(_target: Path): Path
		error("Not supported!")
	end, "aarch64-pc-windows-gnu");
	[ToKey("x86_64", "windows")] = AsMetadata(function(target: Path): Path
		return target:join("x86_64-pc-windows-gnu"):join("release")
	end, "x86_64-pc-windows-gnu");

	[ToKey("aarch64", "linux")] = AsMetadata(function(target: Path): Path
		return target:join("aarch64-unknown-linux-gnu"):join("release")
	end, "aarch64-unknown-linux-gnu");
	[ToKey("x86_64", "linux")] = AsMetadata(function(target: Path): Path
		return target:join("x86_64-unknown-linux-gnu"):join("release")
	end, "x86_64-unknown-linux-gnu");

	[ToKey("aarch64", "macos")] = AsMetadata(function(target: Path): Path
		return target:join("aarch64-apple-darwin"):join("release")
	end, "aarch64-apple-darwin");
	[ToKey("x86_64", "macos")] = AsMetadata(function(target: Path): Path
		return target:join("x86_64-apple-darwin"):join("release")
	end, "x86_64-apple-darwin");
}

local arguments: {
	arch: Architecture,
	destroy: boolean?,
	os: OS,
	verbose: boolean?,
} = parser:parse()
if not next(arguments) then
	parser:error("No arguments provided.")
end

local architecture: Architecture = arguments.arch
if not table.find(ARCHITECTURES, architecture) then
	console.error("Invalid architecture: %q", tostring(architecture))
	process.exit(1)
end

local operatingSystem: OS = arguments.os
if not table.find(OPERATING_SYSTEMS, operatingSystem) then
	console.error("Invalid operating system: %q", tostring(operatingSystem))
	process.exit(1)
end

-- local ON_WINDOWS = process.os == "windows"
local ON_WINDOWS = operatingSystem == "windows"
local TARGET_FOLDER = Path.new("target")

local function GetData(): (Path, string?)
	if architecture == process.arch and operatingSystem == process.os then
		return TARGET_FOLDER:join("release")
	end

	local metadata = ArchitectureMetadata[ToKey(architecture, operatingSystem)]
	if not metadata then
		console.error("Invalid architecture and operating system combination: %q + %q", architecture, operatingSystem)
		process.exit(1)
		error("unreachable")
	end

	return metadata.GetPath(TARGET_FOLDER), metadata.Target
end

local RELEASE_FOLDER, TARGET = GetData()
if arguments.verbose then
	console.log(`Release folder = {RELEASE_FOLDER}`)
	console.log(`Release target = {TARGET}`)
end
local RELEASES_FOLDER = TARGET_FOLDER:join("releases")

local RELEASE_FILE = RELEASE_FOLDER:join(if ON_WINDOWS then "stylua.exe" else "stylua")

local FORMATTERS = Path.new("src"):join("formatters")
local TABLE_FILE = FORMATTERS:join("table.rs")
local ASSIGNMENT_FILE = FORMATTERS:join("assignment.rs")
local FUNCTIONS_FILE = FORMATTERS:join("functions.rs")

local SEPARATOR_STRING = "const MULTI_LINE_SEPARATOR: &str = %q;"
local SEPARATOR_PATTERN = RegEx.new(string.format(SEPARATOR_STRING, "(;|,)"))

local EXPRESSIONS_STRING = "const MAX_EXPRESSIONS: usize = %*;"
local EXPRESSIONS_PATTERN = RegEx.new(string.format(EXPRESSIONS_STRING, "(\\d+|usize::MAX)"))

local ARGUMENTS_STRING = "const MAX_ARGUMENTS: usize = %*;"
local ARGUMENTS_PATTERN = RegEx.new(string.format(ARGUMENTS_STRING, "(\\d+)"))

local function BuildStyLua2(fileName: string, jobType: JobType)
	local command = {"cargo", "b", "--all-features", "--release"}
	if arguments.verbose then
		table.insert(command, "-v")
	end
	if TARGET then
		table.insert(command, "--target")
		table.insert(command, TARGET)
	end

	Execute(command, {stdio = "inherit"}):Assert()

	if not PathFileSystem.IsFileSafe(RELEASE_FILE) then
		console.error(`Release file not found? (checking in {RELEASE_FILE})`)
		process.exit(1)
	end

	if not PathFileSystem.IsDirectorySafe(RELEASES_FOLDER) then
		PathFileSystem.WriteDirectory(RELEASES_FOLDER)
	end

	local baseFileName = if jobType == "dg" then `{fileName}-dg` else fileName
	PathFileSystem.Move(
		RELEASE_FILE,
		RELEASES_FOLDER:join(if ON_WINDOWS then `{baseFileName}.exe` else baseFileName),
		true
	)
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
local function GetArgumentsInverse(fileSource: string, jobType: JobType)
	return ARGUMENTS_PATTERN:replace(fileSource, string.format(ARGUMENTS_STRING, if jobType == "dg" then "50" else "1"))
end

if not PathFileSystem.IsFileSafe(TABLE_FILE) then
	console.warn("table.rs file not found")
	process.exit(1)
end
if not PathFileSystem.IsFileSafe(ASSIGNMENT_FILE) then
	console.warn("assignment.rs file not found")
	process.exit(1)
end
if not PathFileSystem.IsFileSafe(FUNCTIONS_FILE) then
	console.warn("functions.rs file not found")
	process.exit(1)
end

type BuildType = "stylua2" | "stylua2Roact"
type JobType = "hms" | "dg"
type BuildData = {
	BuildType: BuildType,
	JobType: JobType,
	MaxArguments: string,

	TableFileSource: string,
	AssignmentFileSource: string,
	FunctionsFileSource: string,
}

local function DetermineBuildType(): BuildData
	local tableFileSource = PathFileSystem.ReadFile(TABLE_FILE)
	local assignmentFileSource = PathFileSystem.ReadFile(ASSIGNMENT_FILE)
	local functionsFileSource = PathFileSystem.ReadFile(FUNCTIONS_FILE)

	if not SEPARATOR_PATTERN:isMatch(tableFileSource) then
		console.warn("Multi-line separator not found")
		process.exit(1)
	end
	local separatorCapture = SEPARATOR_PATTERN:captures(tableFileSource)
	if not separatorCapture then
		console.warn("Failed to capture multi-line separator?")
		process.exit(1)
		return {
			BuildType = "stylua2";
			JobType = "hms";
			MaxArguments = "";

			TableFileSource = "";
			AssignmentFileSource = "";
			FunctionsFileSource = "";
		}
	end
	local separatorCaptureMatch = separatorCapture:get(1)
	if not separatorCaptureMatch then
		console.warn("Failed to capture multi-line separator type?")
		process.exit(1)

		return {
			BuildType = "stylua2";
			JobType = "hms";
			MaxArguments = "";

			TableFileSource = "";
			AssignmentFileSource = "";
			FunctionsFileSource = "";
		}
	end

	if not EXPRESSIONS_PATTERN:isMatch(assignmentFileSource) then
		console.warn("Max expressions not found")
		process.exit(1)
	end
	local expressionsCapture = EXPRESSIONS_PATTERN:captures(assignmentFileSource)
	if not expressionsCapture then
		console.warn("Failed to capture max expressions?")
		process.exit(1)

		return {
			BuildType = "stylua2";
			JobType = "hms";
			MaxArguments = "";

			TableFileSource = "";
			AssignmentFileSource = "";
			FunctionsFileSource = "";
		}
	end
	local expressionsCaptureMatch = expressionsCapture:get(1)
	if not expressionsCaptureMatch then
		console.warn("Failed to capture max expressions type?")
		process.exit(1)

		return {
			BuildType = "stylua2";
			JobType = "hms";
			MaxArguments = "";

			TableFileSource = "";
			AssignmentFileSource = "";
			FunctionsFileSource = "";
		}
	end

	if not ARGUMENTS_PATTERN:isMatch(functionsFileSource) then
		console.warn("Max arguments not found")
		process.exit(1)
	end
	local argumentsCapture = ARGUMENTS_PATTERN:captures(functionsFileSource)
	if not argumentsCapture then
		console.warn("Failed to capture max arguments?")
		process.exit(1)

		return {
			BuildType = "stylua2";
			JobType = "hms";
			MaxArguments = "";

			TableFileSource = "";
			AssignmentFileSource = "";
			FunctionsFileSource = "";
		}
	end
	local argumentsCaptureMatch = argumentsCapture:get(1)
	if not argumentsCaptureMatch then
		console.warn("Failed to capture max arguments type?")
		process.exit(1)

		return {
			BuildType = "stylua2";
			JobType = "hms";
			MaxArguments = "";

			TableFileSource = "";
			AssignmentFileSource = "";
			FunctionsFileSource = "";
		}
	end

	local captureType: ";" | "," = separatorCaptureMatch.text
	local expression: "1" | "usize::MAX" = expressionsCaptureMatch.text
	local argumentsText = argumentsCaptureMatch.text

	local buildType: BuildType = if captureType == ";" then "stylua2" else "stylua2Roact"
	local jobType: JobType = if expression == "usize::MAX" then "hms" else "dg"

	local argumentsNumber = tonumber(argumentsText)
	if not argumentsNumber then
		console.warn("Failed to capture max arguments number?")
		process.exit(1)

		return {
			BuildType = "stylua2";
			JobType = "hms";
			MaxArguments = "";

			TableFileSource = "";
			AssignmentFileSource = "";
			FunctionsFileSource = "";
		}
	end

	if argumentsNumber == 1 then
		if jobType ~= "dg" then
			argumentsText = "50"
		end
	elseif argumentsNumber == 50 then
		if jobType ~= "hms" then
			argumentsText = "1"
		end
	end

	-- return buildType, jobType, tableFileSource, assignmentFileSource

	return {
		BuildType = buildType;
		JobType = jobType;
		MaxArguments = argumentsText;

		TableFileSource = tableFileSource;
		AssignmentFileSource = assignmentFileSource;
		FunctionsFileSource = functionsFileSource;
	}
end

local function Build(buildType: BuildType, jobType: JobType, tableFileSource: string, _assignmentFileSource: string)
	BuildStyLua2(buildType, jobType)
	-- print(`BuildStyLua2({buildType}, {jobType})`)
	-- task.wait(2)

	PathFileSystem.WriteFile(TABLE_FILE, GetTableInverse(tableFileSource, buildType))

	BuildStyLua2(if buildType == "stylua2" then "stylua2Roact" else "stylua2", jobType)
	-- print(`BuildStyLua2({if buildType == "stylua2" then "stylua2Roact" else "stylua2"}, {jobType})`)
	-- task.wait(2)
	PathFileSystem.WriteFile(TABLE_FILE, tableFileSource)
end

local buildData = DetermineBuildType()

local buildType: BuildType = buildData.BuildType
local jobType: JobType = buildData.JobType

local tableFileSource = buildData.TableFileSource
local assignmentFileSource = buildData.AssignmentFileSource
local functionsFileSource = buildData.FunctionsFileSource

Build(buildType, jobType, tableFileSource, assignmentFileSource)
PathFileSystem.WriteFile(ASSIGNMENT_FILE, GetAssignmentInverse(assignmentFileSource, jobType))
PathFileSystem.WriteFile(FUNCTIONS_FILE, GetArgumentsInverse(functionsFileSource, jobType))
Build(buildType, if jobType == "dg" then "hms" else "dg", tableFileSource, assignmentFileSource)

PathFileSystem.WriteFile(TABLE_FILE, tableFileSource)
PathFileSystem.WriteFile(ASSIGNMENT_FILE, assignmentFileSource)
PathFileSystem.WriteFile(FUNCTIONS_FILE, functionsFileSource)

if arguments.destroy and PathFileSystem.IsDirectorySafe(RELEASE_FOLDER) then
	PathFileSystem.RemoveDirectory(RELEASE_FOLDER)
end
