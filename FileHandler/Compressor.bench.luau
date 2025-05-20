--!strict
--!native

--[[ 
	Benchmark Template: Compressor Module

	Purpose:
		Designed to be used with the Benchmarker plugin to measure the performance
		of compression and decompression operations at different compression levels.

	Notes:
		- You may need to adjust `JSON_ENCODE_MAX_SIZE` in the Compressor module
		  to ensure compatibility with large buffer sizes during performance testing.
		- The buffer created is filled with pseudo-random 16-bit unsigned integers.

	Usage:
		Run this script within the Benchmarker plugin environment. It provides six
		benchmark functions: Compress and Decompress at levels 1, 2, and 3.
]]

local Compressor = require(script.Compressor)

-- Initialize random seed and test input buffer
local randomObject = Random.new(0)
local testSize = 2 ^ 20 -- 1 MiB
local testSource = buffer.create(testSize)

-- Fill buffer with random 32-bit unsigned values
for i = 0, testSize // 4 - 1 do
	buffer.writeu16(testSource, i, randomObject:NextInteger(0, 2 ^ 32 - 1))
end

-- Precompute compressed buffers for each compression level
local lv1Compressed = Compressor.Compress(testSource, 1)
local lv2Compressed = Compressor.Compress(testSource, 2)
local lv3Compressed = Compressor.Compress(testSource, 3)

-- Validate decompression output matches original source
local sourceStr = buffer.tostring(testSource)
assert(buffer.tostring(Compressor.Decompress(lv1Compressed)) == sourceStr, "Decompression failed for level 1")
assert(buffer.tostring(Compressor.Decompress(lv2Compressed)) == sourceStr, "Decompression failed for level 2")
assert(buffer.tostring(Compressor.Decompress(lv3Compressed)) == sourceStr, "Decompression failed for level 3")

-- Log sizes for manual inspection
print("Original size:", #sourceStr)
print("Compressed size (lv1):", #lv1Compressed)
print("Compressed size (lv2):", #lv2Compressed)
print("Compressed size (lv3):", #lv3Compressed)

return {
	ParameterGenerator = function()
		return
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
		
		["Compress lv1"] = function(Profiler)
			Compressor.Compress(testSource, 1)
		end,

		---

		["Decompress lv1"] = function(Profiler)
			Compressor.Decompress(lv1Compressed)
		end,

		---

		["Compress lv2"] = function(Profiler)
			Compressor.Compress(testSource, 2)
		end,

		---

		["Decompress lv2"] = function(Profiler)
			Compressor.Decompress(lv2Compressed)
		end,

		---

		["Compress lv3"] = function(Profiler)
			Compressor.Compress(testSource, 3)
		end,

		---

		["Decompress lv3"] = function(Profiler)
			Compressor.Decompress(lv3Compressed)
		end,

		---

	},
}
