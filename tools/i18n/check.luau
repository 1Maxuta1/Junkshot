--[[
	tools/i18n/check: every language file has exactly the keys of the reference (ru.luau),
	no key twice, and every translation uses only the values its key provides.

	  lune run tools/i18n/check
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local DIR = "src/shared/Localization/Languages"
local REFERENCE = "ru"

local function unescape(text: string): string
	return (text:gsub("\\(.)", function(c)
		return if c == "n" then "\n" elseif c == "t" then "\t" else c
	end))
end

-- { key = translation } plus a list of keys found twice.
local function parse(path: string): ({ [string]: string }, { string }, number)
	local source = fs.readFile(path):gsub("\r\n", "\n")
	local entries: { [string]: string } = {}
	local twice = {}
	local count = 0
	for rawKey, rawValue in source:gmatch('\n%s*%[%s*"(.-[^\\])"%s*%]%s*=%s*"(.-[^\\]?)",') do
		local key, value = unescape(rawKey), unescape(rawValue)
		if entries[key] ~= nil then
			table.insert(twice, key)
		end
		entries[key] = value
		count += 1
	end
	return entries, twice, count
end

local function slots(key: string): number
	local _, n = key:gsub("{}", "")
	return n
end

-- Problems with one translation: values it uses that the key does not have.
local function badPlaceholders(key: string, value: string): string?
	local have = slots(key)
	local sequential = 0
	for digits in value:gmatch("{(%d*)}") do
		if digits == "" then
			sequential += 1
			if sequential > have then
				return "uses more {} than the key has (" .. have .. ")"
			end
		else
			local index = tonumber(digits) :: number
			if index < 1 or index > have then
				return "uses {" .. digits .. "} but the key has " .. have
			end
		end
	end
	return nil
end

local reference, refTwice = parse(`{DIR}/{REFERENCE}.luau`)
local failures = 0
for _, key in refTwice do
	print(`{REFERENCE}: key twice: {key}`)
	failures += 1
end

for _, name in fs.readDir(DIR) do
	local code = name:match("^(%a+)%.luau$")
	if code == nil then
		continue
	end
	local entries, twice, count = parse(`{DIR}/{name}`)
	local problems = {}
	for _, key in twice do
		table.insert(problems, `key twice: {key}`)
	end
	for key in reference do
		if entries[key] == nil then
			table.insert(problems, `missing: {key}`)
		end
	end
	for key, value in entries do
		if reference[key] == nil then
			table.insert(problems, `not in {REFERENCE}: {key}`)
		end
		local bad = badPlaceholders(key, value)
		if bad ~= nil then
			table.insert(problems, `{key} -> {value}: {bad}`)
		end
		if value == "" then
			table.insert(problems, `empty: {key}`)
		end
	end
	table.sort(problems)
	print(`{code}: {count} entries, {#problems} problems`)
	for index, problem in problems do
		if index > 25 then
			print(`  ... and {#problems - 25} more`)
			break
		end
		print(`  {problem}`)
	end
	failures += #problems
end

if failures > 0 then
	process.exit(1)
end
