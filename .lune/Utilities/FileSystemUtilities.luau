--!optimize 2
--!strict

local fs = require("@lune/fs")
local process = require("@lune/process")

local SEPARATOR = if process.os == "windows" then "\\" else "/"

local FileSystemUtilities = {}

function FileSystemUtilities.JustFileName(path: string): string
	return string.match(string.match(path, "^(.+)%..+$") or path, "([^\\/]+)$") or path
end
function FileSystemUtilities.JustFileNameWithExtension(path: string): string
	return string.match(path, "([^\\/]+)$") or path
end

local function WithoutExtension(path: string): string
	return string.match(path, "^(.+)%..+$") or path
end
FileSystemUtilities.WithoutExtension = WithoutExtension

local function GetExtension(path: string): string?
	return string.match(path, "%.([^%.]+)$")
end
FileSystemUtilities.GetExtension = GetExtension

local function Normalize(path: string): string
	return (string.gsub(path, "\\", SEPARATOR))
end
FileSystemUtilities.Normalize = Normalize

local function Join(...: string): string
	local length = select("#", ...)
	local pathArray = table.create(length)

	for index = 1, length do
		local path = select(index, ...)
		if path ~= "" then
			pathArray[index] = Normalize(path)
		end
	end

	return (string.gsub(table.concat(pathArray, SEPARATOR), "[\\/]+", SEPARATOR))
end
FileSystemUtilities.Join = Join

type CreatorFunction = (path: string, contents: string?) -> ()
type SafeCreate =
	& ((name: string, fileType: "File", contents: string) -> string)
	& ((name: string, fileType: "Directory") -> string)

local function GetNewFilePath(withoutExtension: string, index: number, extension: string?): string
	return if extension then `{withoutExtension} ({index}).{extension}` else `{withoutExtension} ({index})`
end

local function SafeCreate(name: string, fileType: "File" | "Directory", contents: string?): string
	local checkerFunction: typeof(fs.isDir) = if fileType == "File" then fs.isFile else fs.isDir
	local creatorFunction = (if fileType == "File" then fs.writeFile else fs.writeDir) :: CreatorFunction

	if not checkerFunction(name) then
		creatorFunction(name, contents)
		return name
	end

	local withoutExtension = WithoutExtension(name)
	local extension = GetExtension(name)
	local index = 1

	local newFilePath = GetNewFilePath(withoutExtension, index, extension)
	while checkerFunction(newFilePath) do
		index += 1
		newFilePath = GetNewFilePath(withoutExtension, index, extension)
	end

	creatorFunction(newFilePath, contents)
	return newFilePath
end
FileSystemUtilities.SafeCreate = SafeCreate :: SafeCreate

function FileSystemUtilities.GetOrCreateDirectory(name: string): ()
	name = Normalize(name)
	if not fs.isDir(name) then
		SafeCreate(name, "Directory")
	end
end

function FileSystemUtilities.RecursivelyCreateDirectory(path: string): ()
	for _, component in string.split(Normalize(path), SEPARATOR) do
		fs.writeDir(component)
	end
end

FileSystemUtilities.PathSeparator = SEPARATOR
FileSystemUtilities.Separator = SEPARATOR
FileSystemUtilities.SEPARATOR = SEPARATOR

FileSystemUtilities.CWD = Normalize(process.cwd)

return table.freeze(FileSystemUtilities)
