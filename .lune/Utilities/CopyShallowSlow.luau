--!optimize 2
--!strict

export type IteratorType = "generalized" | "general" | "pairs" | "next" | "ipairs"
local function AsIteratorType(iteratorType: IteratorType): IteratorType
	return iteratorType
end

local function Generalized<T>(object: T): T
	local newObject = table.create(#(object :: any))
	for key, value in object :: any do
		newObject[key] = value
	end
	return (newObject :: unknown) :: T
end

local COPY_FUNCTIONS: {[IteratorType]: <T>(object: T) -> T} = {
	[AsIteratorType("generalized")] = Generalized;
	[AsIteratorType("general")] = Generalized;
	[AsIteratorType("pairs")] = function<T>(object: T): T
		local newObject = table.create(#(object :: any))
		for key, value in pairs(object :: any) do
			newObject[key] = value
		end
		return (newObject :: unknown) :: T
	end;
	[AsIteratorType("ipairs")] = function<T>(object: T): T
		local newObject = table.create(#(object :: any))
		for key, value in ipairs(object :: any) do
			newObject[key] = value
		end
		return (newObject :: unknown) :: T
	end;
	[AsIteratorType("next")] = function<T>(object: T): T
		local newObject = table.create(#(object :: any))
		for key, value in next, object :: any do
			newObject[key] = value
		end
		return (newObject :: unknown) :: T
	end;
}

local function CopyShallowSlow<T>(object: T, iteratorType: IteratorType?): T
	if type(object) ~= "table" then
		return object
	end

	local copyFunction = COPY_FUNCTIONS[AsIteratorType(iteratorType or "generalized")]
	return copyFunction(object)
end

return CopyShallowSlow
