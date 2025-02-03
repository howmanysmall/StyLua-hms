--!native
--!optimize 2
--!strict

-- excluding the `+` and `*` character, since findOr tests and graphql use them explicitly
local luaPatternCharacters = "([" .. string.gsub("$%^()-[].?", "(.)", "%%%1") .. "])"

-- Implements equivalent functionality to JavaScript's `String.indexOf`,
-- implementing the interface and behaviors defined at:
-- https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/String/indexOf
return function(str: string, searchElement: string, fromIndex: number?): number
	local length = #str
	local fromIndex_ = 1
	if fromIndex then
		fromIndex_ = if fromIndex < 1 then 1 else fromIndex :: number
	end

	if #searchElement == 0 then
		return if fromIndex_ > length then length else fromIndex_
	end

	if fromIndex_ > length then
		return -1
	end

	searchElement = string.gsub(searchElement, luaPatternCharacters, "%%%1")
	local searchElementLength = #searchElement

	for i = fromIndex_, length do
		if string.sub(str, i, i + searchElementLength - 1) == searchElement then
			return i
		end
	end

	return -1
end
