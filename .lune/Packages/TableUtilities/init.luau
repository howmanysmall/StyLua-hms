--!optimize 2
--!strict

local CopyDeep = require("@self/CopyDeep")
local EqualObjects = require("@self/EqualObjects")
local Equals = require("@self/Equals")
local EqualsDeep = require("@self/EqualsDeep")
local FastMerge = require("@self/FastMerge")
local FastMergeDeep = require("@self/FastMergeDeep")
local IsArray = require("@self/IsArray")
local LockDeep = require("@self/LockDeep")
local Repr = require("@self/Repr")

-- TODO: When we get @native in selene (and roblox? don't know if it's on without fflag mods) we should transform some of these to @native

--[=[
	A library that contains various utilities for tables.

	@class TableUtilities
]=]
local TableUtilities = table.freeze({
	CopyDeep = CopyDeep;
	EqualObjects = EqualObjects;
	Equals = Equals;
	EqualsDeep = EqualsDeep;
	FastMerge = FastMerge;
	FastMergeDeep = FastMergeDeep;
	IsArray = IsArray;
	LockDeep = LockDeep;
	Repr = Repr;
})

export type DateTimeFormatType = Repr.DateTimeFormatType
export type Locale = Repr.Locale
export type ReprSettings = Repr.ReprSettings

return TableUtilities
