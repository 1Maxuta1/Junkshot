--!strict
--[[
	Validate: small type/range guards. They take `any` on purpose: use them on anything
	that did not originate from trusted server code (remote arguments, saved data).
	They return booleans and never throw.
]]

local Validate = {}

local UID_PATTERN = "^%x+%-%x+%-%x+%-%x+%-%x+$"
local UID_LENGTH = 36 -- HttpService:GenerateGUID(false)

function Validate.IsFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.IsInteger(value: any, min: number?, max: number?): boolean
	if not Validate.IsFiniteNumber(value) then
		return false
	end
	local n = value :: number
	if n % 1 ~= 0 then
		return false
	end
	if min ~= nil and n < min then
		return false
	end
	if max ~= nil and n > max then
		return false
	end
	return true
end

function Validate.IsString(value: any, minLength: number?, maxLength: number?): boolean
	if type(value) ~= "string" then
		return false
	end
	local length = #value
	if minLength ~= nil and length < minLength then
		return false
	end
	if maxLength ~= nil and length > maxLength then
		return false
	end
	return true
end

-- Item ids are config keys: 1-64 chars of letters, digits and underscores.
function Validate.IsItemId(value: any): boolean
	return Validate.IsString(value, 1, 64) and string.match(value, "^[%w_]+$") ~= nil
end

function Validate.IsUid(value: any): boolean
	return Validate.IsString(value, UID_LENGTH, UID_LENGTH) and string.match(value, UID_PATTERN) ~= nil
end

return Validate
