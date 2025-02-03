--!native
--!optimize 2
--!strict
return function(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
