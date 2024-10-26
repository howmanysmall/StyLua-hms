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

local TARGET_FOLDER = Path.new("target")
local RELEASE_FOLDER = TARGET_FOLDER:join("release")
local RELEASES_FOLDER = TARGET_FOLDER:join("releases")

local RELEASE_FILE = RELEASE_FOLDER:join(if process.os == "windows" then "stylua.exe" else "stylua")

local TABLE_FILE = Path.new("src"):join("formatters"):join("table.rs")

local BASE_STRING = "const MULTI_LINE_SEPARATOR: &str = %q;"
local SEPARATOR_PATTERN = RegEx.new(string.format(BASE_STRING, "(;|,)"))

local function BuildStyLua2(fileName: string)
	Execute({"cargo", "b", "--all-features", "--release"}):Assert()

	if not PathFileSystem.IsFileSafe(RELEASE_FILE) then
		console.error("Release file not found?")
		process.exit(1)
	end

	if not PathFileSystem.IsDirectorySafe(RELEASES_FOLDER) then
		PathFileSystem.WriteDirectory(RELEASES_FOLDER)
	end

	PathFileSystem.Move(
		RELEASE_FILE,
		RELEASES_FOLDER:join(if process.os == "windows" then `{fileName}.exe` else fileName),
		true
	)
end
local function GetInverse(fileSource: string, separator: ";" | ",")
	return SEPARATOR_PATTERN:replace(fileSource, string.format(BASE_STRING, if separator == ";" then "," else ";"))
end

if not PathFileSystem.IsFileSafe(TABLE_FILE) then
	console.warn("table.rs file not found")
	process.exit(1)
end

local fileSource = PathFileSystem.ReadFile(TABLE_FILE)
if not SEPARATOR_PATTERN:isMatch(fileSource) then
	console.warn("Multi-line separator not found")
	process.exit(1)
end

local capture = SEPARATOR_PATTERN:captures(fileSource)
if not capture then
	console.warn("Failed to capture multi-line separator?")
	process.exit(1)
	return
end

local captureMatch = capture:get(1)
if not captureMatch then
	console.warn("Failed to capture multi-line separator type?")
	process.exit(1)
	return
end

local captureType: ";" | "," = captureMatch.text
BuildStyLua2(if captureType == ";" then "stylua2" else "stylua2Roact")
PathFileSystem.WriteFile(TABLE_FILE, GetInverse(fileSource, captureType))
BuildStyLua2(if captureType == ";" then "stylua2Roact" else "stylua2")
PathFileSystem.WriteFile(TABLE_FILE, fileSource)

if DESTROY_MODE and PathFileSystem.IsDirectorySafe(RELEASE_FOLDER) then
	PathFileSystem.RemoveDirectory(RELEASE_FOLDER)
end
