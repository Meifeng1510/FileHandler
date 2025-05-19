--!native
local oldModule = require(script.OldCompressor)
local newModule = require(script.NewCompressor)
local newerModule = require(script.NewerCompressor)

local testSource = buffer.create(2 ^ 20)
for i = 0, buffer.len(testSource) / 2 - 1 do
	buffer.writeu16(testSource, i, math.random(0, 2 ^ 16 - 1))
end

local oldLv1Compressed = oldModule.Compress(testSource, 1)
local newLv1Compressed = newModule.Compress(testSource, 1)
local newerLv1Compressed = newerModule.Compress(testSource, 1)

local oldLv2Compressed = oldModule.Compress(testSource, 2)
local newLv2Compressed = newModule.Compress(testSource, 2)
local newerLv2Compressed = newerModule.Compress(testSource, 2)

local sourceStr = buffer.tostring(testSource)
assert(buffer.tostring(oldModule.Decompress(oldLv1Compressed)) == sourceStr)
assert(buffer.tostring(newModule.Decompress(newLv1Compressed)) == sourceStr)
assert(buffer.tostring(newerModule.Decompress(newerLv1Compressed)) == sourceStr)
assert(buffer.tostring(oldModule.Decompress(oldLv2Compressed)) == sourceStr)
assert(buffer.tostring(newModule.Decompress(newLv2Compressed)) == sourceStr)
assert(buffer.tostring(newerModule.Decompress(newerLv2Compressed)) == sourceStr)

print(oldLv1Compressed == newLv1Compressed)
print(newLv1Compressed == newerLv1Compressed)

print(oldLv2Compressed == newLv2Compressed)
print(newLv2Compressed == newerLv2Compressed)

print(#oldLv1Compressed)
print(#newLv1Compressed)
print(#newerLv1Compressed)
print(#oldLv2Compressed)
print(#newLv2Compressed)
print(#newerLv2Compressed)

return {
	ParameterGenerator = function()
		return testSource
	end,

	BeforeAll = function() end,
	AfterAll = function() end,
	BeforeEach = function() end,
	AfterEach = function() end,

	------------------------------------------------------------------------------------

	Iterations = 1000,
	MaxExecutionTime = 0.2,

	PauseInterval = {
		Type = "RunTime", -- options: "Iteration" | "RunTime"

		--[[
			Properties
			- IterationCount (if selected option is "Iteration", unit is in iteration)
			- ExecutionTime (if selected option is "RunTime", unit is in second)
		]]

		ExecutionTime = 1,
	},

	InlineTests = false, -- options: false | {RepeatCount: number, OptimizeLevel: number, Native: boolean, CacheSource: true | false}

	------------------------------------------------------------------------------------

	Functions = {
		["Old Compress lv1"] = function(Profiler, value)
			oldModule.Compress(value, 1)
		end,

		["New Compress lv1"] = function(Profiler, value)
			newModule.Compress(value, 1)
		end,

		["Newer Compress lv1"] = function(Profiler, value)
			newerModule.Compress(value, 1)
		end,

		---

		--["Old Decompress lv1"] = function(Profiler, value)
		--	oldModule.Decompress(oldLv1Compressed)
		--end,

		--["New Decompress lv1"] = function(Profiler, value)
		--	newModule.Decompress(newLv1Compressed)
		--end,

		--["Newer Decompress lv1"] = function(Profiler, value)
		--	newerModule.Decompress(newLv1Compressed)
		--end,

		---

		["Old Compress lv2"] = function(Profiler, value)
			oldModule.Compress(value, 2)
		end,

		["New Compress lv2"] = function(Profiler, value)
			newModule.Compress(value, 2)
		end,

		["Newer Compress lv2"] = function(Profiler, value)
			newerModule.Compress(value, 2)
		end,

		---

		--["Old Decompress lv2"] = function(Profiler, value)
		--	oldModule.Decompress(oldLv1Compressed)
		--end,

		--["New Decompress lv2"] = function(Profiler, value)
		--	newModule.Decompress(newLv1Compressed)
		--end,

		--["Newer Decompress lv2"] = function(Profiler, value)
		--	newerModule.Decompress(newLv1Compressed)
		--end,
	},
}
