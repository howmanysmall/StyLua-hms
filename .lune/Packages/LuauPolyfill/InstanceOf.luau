--!native
--!optimize 2
--!strict
-- polyfill for https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/instanceof
local __DEV__ = _G.__DEV__

-- FIXME Luau: typing class as Object gives: Type '{ @metatable {| __call: <a>(a, ...any) -> Error, __tostring: <b, c>({+ message: b, name: c +}) -> string |}, Error }' could not be converted into 'table'
local function instanceof(tbl: any, class: any): boolean
	if __DEV__ then
		assert(type(class) == "table", "Received a non-table as the second argument for instanceof")
	end

	if type(tbl) ~= "table" then
		return false
	end

	if type(class) == "table" and type(class.instanceof) == "function" then
		return class.instanceof(tbl)
	end

	local ok, hasNew = pcall(function()
		return class.new ~= nil and tbl.new == class.new
	end)

	if ok and hasNew then
		return true
	end

	local seen = {[tbl] = true}

	while tbl and type(tbl) == "table" do
		tbl = getmetatable(tbl)
		if type(tbl) == "table" then
			tbl = tbl.__index

			if tbl == class then
				return true
			end
		end

		-- if we still have a valid table then check against seen
		if type(tbl) == "table" then
			if seen[tbl] then
				return false
			end

			seen[tbl] = true
		end
	end

	return false
end

return instanceof
