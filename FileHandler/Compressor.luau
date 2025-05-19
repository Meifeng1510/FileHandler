--!strict
--!native

-- Made by your lovely @meifeng_ft

--[[
	Custom Buffer Serialization and Compression Library
	-------------------------------------------------
	Author: @meifeng_ft
	Date: 2025-05-19 (Last Updated)

	Description:
	This module provides functions to compress and decompress Luau values,
	particularly buffers, using various encoding schemes. It's optimized
	for performance and supports chunking for large data exceeding
	Roblox's HttpService JSON string limits for buffers.

	Features:
	- Multiple compression/encoding levels.
	- Automatic chunking and reassembly of large buffers.

	Important Notes:
	- Relies on the specific JSON structure produced by HttpService:JSONEncode for buffers.
	- Decoder functions omit error handling for performance; ensure input data is valid.
]]

--[[
	Runs with ~8MB of memory
	- 4MB of map memory
	- 204 KB of native code memory
]]

--// Types \\--

--// Services \\--

local HttpService = game:GetService("HttpService")

--// Variables \\--

--// Types (u8)

local TYPE_BOOLEAN_FALSE = 0
local TYPE_BOOLEAN_TRUE = 1
local TYPE_STRING = 2
local TYPE_DOUBLE = 3
local TYPE_INTERGER_ZERO = 4
local TYPE_INTEGER_U8 = 5
local TYPE_INTEGER_U16 = 6
local TYPE_INTEGER_U24 = 7
local TYPE_INTEGER_U32 = 8
local TYPE_INTEGER_U40 = 9
local TYPE_INTEGER_U48 = 10
local TYPE_INTEGER_U52 = 11
local TYPE_INTEGER_N8 = 12
local TYPE_INTEGER_N16 = 13
local TYPE_INTEGER_N24 = 14
local TYPE_INTEGER_N32 = 15
local TYPE_INTEGER_N40 = 16
local TYPE_INTEGER_N48 = 17
local TYPE_INTEGER_N52 = 18
local TYPE_ARRAY = 19
local TYPE_DICTIONARY = 20
local TYPE_TABLE_TERMINATOR = 21
local TYPE_BUFFER = 22
local TYPE_NIL = 23

--// Base Converter

local BASE64_CHARS = ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"):split("")

local BASE64_MAP: { [any]: any } = {} -- 4,160 Bytes
local DOUBLE_BASE64_MAP: { [any]: any } = {} -- 270,336 Bytes

for firstCharIndex, firstChar in BASE64_CHARS do
	local firstValue = firstCharIndex - 1

	BASE64_MAP[firstChar] = firstValue
	BASE64_MAP[firstValue] = firstChar

	for secondCharIndex, secondChar in BASE64_CHARS do
		local secondValue = secondCharIndex - 1
		local key = firstChar .. secondChar
		local value = firstValue + secondValue * 64
		DOUBLE_BASE64_MAP[key] = value
		DOUBLE_BASE64_MAP[value] = key
	end
end

local BASE256_MAP: { [any]: any } = {} -- 16,640 Bytes
local DOUBLE_BASE256_MAP: { [any]: any } = {} -- 4,259,840 Bytes

for firstByteValue = 0, 255 do
	local firstChar = string.char(firstByteValue)

	BASE256_MAP[firstChar] = firstByteValue
	BASE256_MAP[firstByteValue] = firstChar

	for secondByteValue = 0, 255 do
		local key = firstChar .. string.char(secondByteValue)
		local value = firstByteValue + secondByteValue * 256
		DOUBLE_BASE256_MAP[key] = value
		DOUBLE_BASE256_MAP[value] = key
	end
end

--// Decode Id

-- These single-character IDs are prefixed to the data to indicate the encoding scheme.
-- Any character can be used as encoding id, but the following characters are chosen to avoid control characters and whitespace.
local BASE64_ENCODE_ID = [[!]] -- string.char(33)
local BASE256_ENCODE_ID = [["]] -- string.char(34)
local ZSTD_BASE64_ENCODE_ID = [[#]] -- string.char(35)
local ZSTD_BASE256_ENCODE_ID = [[$]] -- string.char(36)
local SPLIT_JSON_ENCODE_ID = [[%]] -- string.char(37)
local SPLIT_BASE64_ENCODE_ID = [[&]] -- string.char(38)
local SPLIT_BASE256_ENCODE_ID = [[']] -- string.char(39)

-- Numerical indices for array
local PURE_JSON_ENCODER_ID = 1
local STRIP_JSON_ENCODER_ID = 2
local BASE256_JSON_ENCODER_ID = 3

--// Constants

local JSON_ENCODE_MAX_SIZE = 2 ^ 25 + 2 ^ 24 + 2 ^ 21 -- 52,428,800 bytes (Approx 50 MiB). Max sizes HttpService can handle.
local BUFFER_MAX_SIZE = 2 ^ 30 -- 1,073,741,824 bytes (1 GiB). The largest size buffer can be allocated with.

-- buffer is not used as strings are more efficient in native
-- local U32_BUFFER = buffer.create(4)

--// Functions \\--

-- Packs a 32-bit unsigned integer into a 4-byte string (big-endian).
local function packU32(value: number): string
	return string.char(value // 2 ^ 24, value // 2 ^ 16 % 2 ^ 8, value // 2 ^ 8 % 2 ^ 8, value % 2 ^ 8)
	-- buffer.writeu32(U32_BUFFER, 0, value)
	-- return buffer.tostring(U32_BUFFER)
end

-- Unpacks a 32-bit unsigned integer from a 4-byte string (big-endian).
local function unpackU32(str: string): number
	local a1, a2, a3, a4 = string.byte(str, 1, 4)
	return a1 * 2 ^ 24 + a2 * 2 ^ 16 + a3 * 2 ^ 8 + a4
	-- buffer.writestring(U32_BUFFER, 0, str)
	-- return buffer.readu32(U32_BUFFER, 0)
end

local function base64ToBase256(str: string): string
	local base64Len = #str
	local base256Len = math.ceil(base64Len * 0.75)

	local resultBuffer = buffer.create(base256Len + 1)

	local single_base64_map = BASE64_MAP
	local double_base64_map = DOUBLE_BASE64_MAP
	local offset = 1

	local remainderChars = base64Len % 4

	-- Process complete 4-character chunks
	for chunkStart = 1, base64Len - 4, 4 do
		-- Get first two and last two characters from the chunk
		local firstTwoChars = string.sub(str, chunkStart, chunkStart + 1)
		local lastTwoChars = string.sub(str, chunkStart + 2, chunkStart + 3)

		-- Convert to a 24-bit value and then to three Base256 characters
		local value = double_base64_map[firstTwoChars] * 4096 + double_base64_map[lastTwoChars]
		buffer.writeu32(resultBuffer, offset, value)
		offset = offset + 3
	end

	-- Handle remaining characters
	if remainderChars == 0 then
		-- Get first two and last two characters from the chunk
		local firstTwoChars = string.sub(str, base64Len - 3, base64Len - 2)
		local lastTwoChars = string.sub(str, base64Len - 1)

		-- Convert to a 24-bit value and then to three Base256 characters
		local value = double_base64_map[firstTwoChars] * 4096 + double_base64_map[lastTwoChars]
		buffer.writeu16(resultBuffer, offset, value)
		buffer.writeu8(resultBuffer, offset + 2, value / 2 ^ 16)
	elseif remainderChars == 1 then
		-- Single character remaining (6 bits)
		local value = single_base64_map[string.sub(str, base64Len, base64Len)]
		buffer.writeu8(resultBuffer, offset, value)
	elseif remainderChars == 2 then
		-- Two characters remaining (12 bits)
		local value = double_base64_map[string.sub(str, base64Len - 1, base64Len)]
		buffer.writeu16(resultBuffer, offset, value)
	else
		-- Three characters remaining (18 bits)
		local firstTwoChars = string.sub(str, base64Len - 2, base64Len - 1)
		local lastChar = string.sub(str, base64Len, base64Len)

		-- Convert to an 18-bit value and then to three Base256 characters
		local value = double_base64_map[firstTwoChars] * 64 + single_base64_map[lastChar]
		buffer.writeu16(resultBuffer, offset, value)
		buffer.writeu8(resultBuffer, offset + 2, value / 2 ^ 16)
		buffer.writeu8(resultBuffer, 0, 1)
	end

	return buffer.tostring(resultBuffer)
end

local function base256ToBase64(str: string): string
	local stringLen = #str
	local base256Len = stringLen - 1
	local base64Len = math.ceil(base256Len * (4 / 3))

	local resultTable = table.create(base64Len // 2)
	local is3Bits = string.sub(str, 1, 1) == string.char(1)

	local single_base256_map = BASE256_MAP
	local double_base256_map = DOUBLE_BASE256_MAP
	local double_base64_map = DOUBLE_BASE64_MAP
	local single_base64_map = BASE64_MAP

	local insertIndex = 1
	local remainderChars = is3Bits and 3 or base256Len % 3

	-- Process complete 3-character chunks
	for chunkStart = 2, stringLen - remainderChars, 3 do
		-- Get first character and last two characters from the chunk
		local firstChar = string.sub(str, chunkStart, chunkStart)
		local lastTwoChars = string.sub(str, chunkStart + 1, chunkStart + 2)

		-- Convert to a 24-bit value and then to two 12-bit Base64 values
		local value = single_base256_map[firstChar] + double_base256_map[lastTwoChars] * 256
		resultTable[insertIndex] = double_base64_map[value // 4096]
		resultTable[insertIndex + 1] = double_base64_map[value % 4096]
		insertIndex = insertIndex + 2
	end

	-- Handle remaining characters
	if remainderChars > 0 then
		if remainderChars == 1 then
			-- Single character remaining (6 bits)
			local value = single_base256_map[string.sub(str, stringLen, stringLen)]
			resultTable[insertIndex] = single_base64_map[value] -- value must be lower than 64
		elseif remainderChars == 2 then
			-- Two characters remaining (12 bits)
			local value = double_base256_map[string.sub(str, stringLen - 1, stringLen)]
			resultTable[insertIndex] = double_base64_map[value]
		else
			-- Three characters remaining (18 bits)
			local firstTwoChars = string.sub(str, stringLen - 2, stringLen - 1)
			local lastChar = string.sub(str, stringLen, stringLen)

			local value = double_base256_map[firstTwoChars] + single_base256_map[lastChar] * 65536
			resultTable[insertIndex] = double_base64_map[value // 64]
			resultTable[insertIndex + 1] = single_base64_map[value % 64]
		end
	end

	return table.concat(resultTable)
end

local function getSize(value: unknown): number
	local valueType = type(value)

	if valueType == "table" then
		local length = #(value :: {})
		local tblSize = length + 2

		if length > 0 then -- array
			assert(next(value :: {}, length) == nil, "Mixed table not allowed")
			for _, arrayValue in value :: {} do
				tblSize += getSize(arrayValue) - 1
			end
		else -- dictionary
			for tblKey, tblValue in value :: {} do
				tblSize += getSize(tblKey) + getSize(tblValue)
			end
		end

		return tblSize
	elseif valueType == "boolean" then
		return 2
	elseif valueType == "string" then
		local length = #(value :: string)
		return length // 2 ^ 7 + length + 2
	elseif valueType == "number" then
		local num = value :: number

		if math.floor(num) == num and math.abs(num) < 2 ^ 52 then -- integer
			if num == 0 then return 2 end
			return math.ceil((math.log(math.abs(num), 2) + 1) / 8) + 1
		else -- float
			return 9
		end
	elseif valueType == "buffer" then
		local bufferLen = buffer.len(value :: buffer)
		return bufferLen + bufferLen // 2 ^ 7 + 2
	else
		error(`Unknown DataType {valueType}`)
	end
end

local function writeValue(valueBuffer: buffer, offset: number, value: unknown): number
	local valueType = type(value)

	if valueType == "table" then
		local length = #(value :: {})

		if length > 0 then -- array
			buffer.writeu8(valueBuffer, offset, TYPE_ARRAY)
			offset += 1

			for i = 1, length do
				local arrayValue = (value :: {})[i]
				offset = writeValue(valueBuffer, offset, arrayValue)
			end

			buffer.writeu8(valueBuffer, offset, TYPE_TABLE_TERMINATOR)
			return offset + 1
		else -- dictionary
			buffer.writeu8(valueBuffer, offset, TYPE_DICTIONARY)
			offset += 1

			for tblKey, tblValue in value :: {} do
				offset = writeValue(valueBuffer, offset, tblKey)
				offset = writeValue(valueBuffer, offset, tblValue)
			end

			buffer.writeu8(valueBuffer, offset, TYPE_TABLE_TERMINATOR)
			return offset + 1
		end
	elseif valueType == "boolean" then
		if value == true then
			buffer.writeu8(valueBuffer, offset, TYPE_BOOLEAN_TRUE)
		else
			buffer.writeu8(valueBuffer, offset, TYPE_BOOLEAN_FALSE)
		end
		return offset + 1
	elseif valueType == "string" then
		buffer.writeu8(valueBuffer, offset, TYPE_STRING)
		offset += 1

		local length = #(value :: string)

		while length >= 2 ^ 7 do
			local u7 = length % 2 ^ 7
			buffer.writeu8(valueBuffer, offset, u7 * 2 + 1)
			offset += 1
			length //= 2 ^ 7
		end

		buffer.writeu8(valueBuffer, offset, length * 2)
		offset += 1
		buffer.writestring(valueBuffer, offset, value :: string)

		return offset + length
	elseif valueType == "number" then
		if math.floor(value :: number) == value and math.abs(value :: number) < 2 ^ 52 then -- is an integer
			if value == 0 then
				buffer.writeu8(valueBuffer, offset, TYPE_INTERGER_ZERO)
				return offset + 1
			elseif (value :: number) < 0 then
				value = -(value :: number)
				if (value :: number) < 2 ^ 8 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_N8)
					offset += 1
					buffer.writeu8(valueBuffer, offset, value :: number)
					return offset + 1
				elseif (value :: number) < 2 ^ 16 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_N16)
					offset += 1
					buffer.writeu16(valueBuffer, offset, value :: number)
					return offset + 2
				elseif (value :: number) < 2 ^ 24 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_N24)
					offset += 1
					buffer.writeu16(valueBuffer, offset, value :: number)
					buffer.writeu8(valueBuffer, offset + 2, value :: number // 2 ^ 16)
					return offset + 3
				elseif (value :: number) < 2 ^ 32 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_N32)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					return offset + 4
				elseif (value :: number) < 2 ^ 40 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_N40)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					buffer.writeu8(valueBuffer, offset + 4, (value :: number) // 2 ^ 32)
					return offset + 5
				elseif (value :: number) < 2 ^ 48 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_N48)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					buffer.writeu16(valueBuffer, offset + 4, (value :: number) // 2 ^ 32)
					return offset + 6
				elseif (value :: number) < 2 ^ 52 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_N52)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					buffer.writeu16(valueBuffer, offset + 4, value :: number // 2 ^ 32)
					buffer.writeu8(valueBuffer, offset + 6, value :: number // 2 ^ 48)
					return offset + 7
				else
					error("Invalid Value")
				end
			else
				if (value :: number) < 2 ^ 8 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_U8)
					offset += 1
					buffer.writeu8(valueBuffer, offset, value :: number)
					return offset + 1
				elseif (value :: number) < 2 ^ 16 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_U16)
					offset += 1
					buffer.writeu16(valueBuffer, offset, value :: number)
					return offset + 2
				elseif (value :: number) < 2 ^ 24 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_U24)
					offset += 1
					buffer.writeu16(valueBuffer, offset, value :: number)
					buffer.writeu8(valueBuffer, offset + 2, value :: number // 2 ^ 16)
					return offset + 3
				elseif (value :: number) < 2 ^ 32 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_U32)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					return offset + 4
				elseif (value :: number) < 2 ^ 40 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_U40)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					buffer.writeu8(valueBuffer, offset + 4, (value :: number) // 2 ^ 32)
					return offset + 5
				elseif (value :: number) < 2 ^ 48 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_U48)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					buffer.writeu16(valueBuffer, offset + 4, (value :: number) // 2 ^ 32)
					return offset + 6
				elseif (value :: number) < 2 ^ 52 then
					buffer.writeu8(valueBuffer, offset, TYPE_INTEGER_U52)
					offset += 1
					buffer.writeu32(valueBuffer, offset, value :: number)
					buffer.writeu16(valueBuffer, offset + 4, value :: number // 2 ^ 32)
					buffer.writeu8(valueBuffer, offset + 6, value :: number // 2 ^ 48)
					return offset + 7
				else
					error("Invalid Value")
				end
			end
		else -- is a float
			buffer.writeu8(valueBuffer, offset, TYPE_DOUBLE)
			buffer.writef64(valueBuffer, offset + 1, value :: number)
			return offset + 9
		end
	elseif valueType == "buffer" then
		buffer.writeu8(valueBuffer, offset, TYPE_BUFFER)
		offset += 1
		local length = buffer.len(value :: buffer)

		while length >= 2 ^ 7 do
			local u7 = length % 2 ^ 7
			buffer.writeu8(valueBuffer, offset, u7 * 2 + 1)
			offset += 1
			length //= 2 ^ 7
		end

		buffer.writeu8(valueBuffer, offset, length * 2)
		offset += 1

		buffer.copy(valueBuffer, offset, value :: buffer)
		return offset + length
	elseif valueType == "nil" then
		buffer.writeu8(valueBuffer, offset, TYPE_NIL)
		return offset + 1
	else
		error(`Unknown DataType {valueType}`)
	end
end

-- Max VLQ is 4 bytes
-- DataStore max size is 4MB, so string length cannot exceed 2^22
-- Same reasoning for buffer and table, although table also have another reason
-- Table itself have a size limit of 2^24, so it cannot exceed 4 bytes
local function readVariableLength(valueBuffer: buffer, offset: number): (number, number)
	local byte = buffer.readu8(valueBuffer, offset)
	if byte % 2 == 0 then return byte / 2, offset + 1 end

	local length = (byte - 1) / 2
	byte = buffer.readu8(valueBuffer, offset + 1)

	if byte % 2 == 0 then return length + byte * 2 ^ 6, offset + 2 end

	length = length + (byte - 1) * 2 ^ 6

	byte = buffer.readu8(valueBuffer, offset + 2)
	if byte % 2 == 0 then return length + byte * 2 ^ 13, offset + 3 end

	length = length + (byte - 1) * 2 ^ 13

	byte = buffer.readu8(valueBuffer, offset + 3)
	return length + byte * 2 ^ 20, offset + 4
end

local function deserializeValue(valueBuffer: buffer, offset: number): (any, number)
	local valueType = buffer.readu8(valueBuffer, offset)
	offset += 1

	if valueType == TYPE_ARRAY then
		local result = {}
		local i = 1
		while true do
			local arrayValue, newOffset = deserializeValue(valueBuffer, offset)
			if newOffset == nil then
				offset = arrayValue
				break
			end
			offset = newOffset
			result[i] = arrayValue
			i = i + 1
		end
		return result, offset
	elseif valueType == TYPE_DICTIONARY then
		local result = {}
		while true do
			local tblKey, keyOffset = deserializeValue(valueBuffer, offset)
			if keyOffset == nil then
				offset = tblKey
				break
			end
			local tblValue, valueOffset = deserializeValue(valueBuffer, keyOffset)
			result[tblKey] = tblValue
			offset = valueOffset
		end
		return result, offset
	elseif valueType == TYPE_BOOLEAN_TRUE then
		return true, offset
	elseif valueType == TYPE_BOOLEAN_FALSE then
		return false, offset
	elseif valueType == TYPE_STRING then
		local length, newOffset = readVariableLength(valueBuffer, offset)
		local str = buffer.readstring(valueBuffer, newOffset, length)
		offset = newOffset + length -- Move past the string data
		return str, offset
	elseif valueType == TYPE_INTERGER_ZERO then
		return 0, offset
	elseif valueType == TYPE_INTEGER_N8 then
		local value = buffer.readu8(valueBuffer, offset)
		return -value, offset + 1
	elseif valueType == TYPE_INTEGER_N16 then
		local value = buffer.readu16(valueBuffer, offset)
		return -value, offset + 2
	elseif valueType == TYPE_INTEGER_N24 then
		local b1 = buffer.readu16(valueBuffer, offset)
		local b2 = buffer.readu8(valueBuffer, offset + 2)
		local value = b1 + b2 * 65536
		return -value, offset + 3
	elseif valueType == TYPE_INTEGER_N32 then
		local value = buffer.readu32(valueBuffer, offset)
		return -value, offset + 4
	elseif valueType == TYPE_INTEGER_N40 then
		local low = buffer.readu32(valueBuffer, offset)
		local high = buffer.readu8(valueBuffer, offset + 4)
		local value = low + high * (2 ^ 32)
		return -value, offset + 5
	elseif valueType == TYPE_INTEGER_N48 then
		local low = buffer.readu32(valueBuffer, offset)
		local high = buffer.readu16(valueBuffer, offset + 4)
		local value = low + high * (2 ^ 32)
		return -value, offset + 6
	elseif valueType == TYPE_INTEGER_N52 then
		local low = buffer.readu32(valueBuffer, offset)
		local high = buffer.readu16(valueBuffer, offset + 4)
		local higher = buffer.readu8(valueBuffer, offset + 6)
		local value = low + high * (2 ^ 32) + higher * (2 ^ 48)
		return -value, offset + 7
	elseif valueType == TYPE_INTEGER_U8 then
		local value = buffer.readu8(valueBuffer, offset)
		return value, offset + 1
	elseif valueType == TYPE_INTEGER_U16 then
		local value = buffer.readu16(valueBuffer, offset)
		return value, offset + 2
	elseif valueType == TYPE_INTEGER_U24 then
		local b1 = buffer.readu16(valueBuffer, offset)
		local b2 = buffer.readu8(valueBuffer, offset + 2)
		local value = b1 + b2 * 65536
		return value, offset + 3
	elseif valueType == TYPE_INTEGER_U32 then
		local value = buffer.readu32(valueBuffer, offset)
		return value, offset + 4
	elseif valueType == TYPE_INTEGER_U40 then
		local low = buffer.readu32(valueBuffer, offset)
		local high = buffer.readu8(valueBuffer, offset + 4)
		local value = low + high * (2 ^ 32)
		return value, offset + 5
	elseif valueType == TYPE_INTEGER_U48 then
		local low = buffer.readu32(valueBuffer, offset)
		local high = buffer.readu16(valueBuffer, offset + 4)
		local value = low + high * (2 ^ 32)
		return value, offset + 6
	elseif valueType == TYPE_INTEGER_U52 then
		local low = buffer.readu32(valueBuffer, offset)
		local high = buffer.readu16(valueBuffer, offset + 4)
		local higher = buffer.readu8(valueBuffer, offset + 6)
		local value = low + high * (2 ^ 32) + higher * (2 ^ 48)
		return value, offset + 7
	elseif valueType == TYPE_DOUBLE then
		local value = buffer.readf64(valueBuffer, offset)
		return value, offset + 8
	elseif valueType == TYPE_TABLE_TERMINATOR then
		return offset, nil :: any
	elseif valueType == TYPE_BUFFER then
		local length, newOffset = readVariableLength(valueBuffer, offset)
		local b = buffer.create(length)
		buffer.copy(b, 0, valueBuffer, newOffset, length)

		offset = newOffset + length -- Move past the buffer data
		return b, offset
	elseif valueType == TYPE_NIL then
		return nil, offset
	else
		error(`Unknown data type identifier {valueType} encountered at offset {offset - 1}`)
	end
end

--// Buffer JSON Template

--[[
	Pre-defined string parts for constructing JSON objects that wrap buffer data.
	This avoids repeated string concatenations and allocations during encoding,
	improving performance when dealing with many small buffers or chunks.
	These templates rely on the known structure of JSON data produced by
	HttpService:JSONEncode for buffers (e.g., {"m":null,"t":"buffer","base64":"..."}).
	If Roblox changes this format, these templates and related offsets MUST be updated.

	Compression Bases:
	- "base64": Standard Base64 encoding, typically used for smaller or high-entropy buffers
	  where compression would be ineffective or counterproductive.
	- "zbase64": Base64 encoding of Zstandard-compressed data, used for larger or low-entropy buffers
	  where repeated patterns make compression more effective.
]]

-- For non-ZSTD compressed data
local base64ConcatTbl = table.create(3)
base64ConcatTbl[1] = [[{"m":null,"t":"buffer","base64":"]]
base64ConcatTbl[3] = [["}]]

-- For non-ZSTD compressed data, converted to Base256 (requires padding for Base64 reconstruction)
local base256ConcatTbl = table.create(4)
base256ConcatTbl[1] = [[{"m":null,"t":"buffer","base64":"]]
base256ConcatTbl[4] = [["}]]

-- For ZSTD compressed data
local zstd_base64ConcatTbl = table.create(3)
zstd_base64ConcatTbl[1] = [[{"m":null,"t":"buffer","zbase64":"]]
zstd_base64ConcatTbl[3] = [["}]]

-- For ZSTD compressed data, converted to Base256 (requires padding for Base64 reconstruction)
local zstd_base256ConcatTbl = table.create(4)
zstd_base256ConcatTbl[1] = [[{"m":null,"t":"buffer","zbase64":"]]
zstd_base256ConcatTbl[4] = [["}]]

-- String slicing offsets (1-based) for extracting data from HttpService:JSONEncode output.
-- Example JSON: {"m":null,"t":"buffer","base64":"DATA"}, {"m":null,"t":"buffer","zbase64":"DATA"}
local BASE_METADATA_OFFSET = 25 -- Start index to check for "base64" or "zbase64" key.
local BASE64_DATA_START_OFFSET = 34 -- Start index of actual data for "base64" key.
local ZSTD_BASE64_DATA_START_OFFSET = 35 -- Start index of actual data for "zbase64" key.
local BASE64_DATA_END_OFFSET = -3 -- End index of data (relative to end of string, before '"}').
local ZSTD_BASE64_DATA_END_OFFSET = -3 -- Same as above.

--[[
	BufferDecoder
	- This function is used to decode the buffer data from the encoded string.
	- It takes the encoded string as input and returns the decoded buffer.

	There are no error handling from invalid data format for performance reason (the code will simply error internally).
	There are multiple duplicate logics, but helper functions cannot be used for performance reason
]]
local BufferDecoder = {
	[SPLIT_JSON_ENCODE_ID] = function(encodedData: string)
		local bufferAmount = string.byte(string.sub(encodedData, 1, 1))
		local lastDataLengthBytes = string.sub(encodedData, bufferAmount * 4 - 2, bufferAmount * 4 + 1)
		local lastDataLength = unpackU32(lastDataLengthBytes)

		local lastBufferData = string.sub(encodedData, -lastDataLength)
		local lastBuffer = HttpService:JSONDecode(lastBufferData)

		-- Calculate total buffer size needed
		local lastBufferSize = buffer.len(lastBuffer)
		local totalSize = (bufferAmount - 1) * JSON_ENCODE_MAX_SIZE + lastBufferSize

		-- Create the final buffer and copy all chunks
		local resultBuffer = buffer.create(totalSize)
		buffer.copy(resultBuffer, (bufferAmount - 1) * JSON_ENCODE_MAX_SIZE, lastBuffer)
		lastBuffer = nil

		local dataCursor = bufferAmount * 4 + 2
		for i = 1, bufferAmount - 1 do
			local lengthCursor = i * 4 - 2
			local lengthBytes = string.sub(encodedData, lengthCursor, lengthCursor + 3)
			local dataLength = unpackU32(lengthBytes)

			local bufferData = string.sub(encodedData, dataCursor, dataCursor + dataLength - 1)
			dataCursor += dataLength

			local dataBuffer = HttpService:JSONDecode(bufferData)
			buffer.copy(resultBuffer, (i - 1) * JSON_ENCODE_MAX_SIZE, dataBuffer)
		end

		return resultBuffer
	end,

	[BASE64_ENCODE_ID] = function(encodedData: string)
		local concatTbl = base64ConcatTbl
		concatTbl[2] = encodedData

		local valueBuffer = HttpService:JSONDecode((table.concat(concatTbl)))
		return valueBuffer
	end,

	[SPLIT_BASE64_ENCODE_ID] = function(encodedData: string)
		local bufferAmount = string.byte(string.sub(encodedData, 1, 1))
		local lastDataLengthBytes = string.sub(encodedData, bufferAmount * 4 - 2, bufferAmount * 4 + 1)
		local lastDataLength = unpackU32(lastDataLengthBytes)

		local lastBufferData = string.sub(encodedData, -lastDataLength)
		local lastBufferEncodeType = string.sub(encodedData, -lastDataLength - 1, -lastDataLength - 1)

		local lastBufferConcatTbl = if lastBufferEncodeType == BASE64_ENCODE_ID
			then base64ConcatTbl
			else zstd_base64ConcatTbl

		lastBufferConcatTbl[2] = lastBufferData
		local lastBuffer = HttpService:JSONDecode((table.concat(lastBufferConcatTbl)))

		-- Calculate total buffer size needed
		local lastBufferSize = buffer.len(lastBuffer)
		local totalSize = (bufferAmount - 1) * JSON_ENCODE_MAX_SIZE + lastBufferSize

		-- Create the final buffer and copy all chunks
		local resultBuffer = buffer.create(totalSize)
		buffer.copy(resultBuffer, (bufferAmount - 1) * JSON_ENCODE_MAX_SIZE, lastBuffer)
		lastBuffer = nil

		local dataCursor = bufferAmount * 4 + 2
		for i = 1, bufferAmount - 1 do
			local lengthCursor = i * 4 - 2
			local lengthBytes = string.sub(encodedData, lengthCursor, lengthCursor + 3)
			local dataLength = unpackU32(lengthBytes)

			local bufferEncodeType = string.sub(encodedData, dataCursor, dataCursor)
			local bufferData = string.sub(encodedData, dataCursor + 1, dataCursor + dataLength)
			dataCursor += dataLength + 1

			local bufferConcatTbl = if bufferEncodeType == BASE64_ENCODE_ID
				then base64ConcatTbl
				else zstd_base64ConcatTbl

			bufferConcatTbl[2] = bufferData
			local dataBuffer = HttpService:JSONDecode((table.concat(bufferConcatTbl)))
			buffer.copy(resultBuffer, (i - 1) * JSON_ENCODE_MAX_SIZE, dataBuffer)
		end

		return resultBuffer
	end,

	[BASE256_ENCODE_ID] = function(encodedData: string)
		local base64Data = base256ToBase64(encodedData)
		local padding = string.rep("=", (4 - #base64Data % 4) % 4)

		local concatTbl = base256ConcatTbl
		concatTbl[2] = base64Data
		concatTbl[3] = padding

		local valueBuffer = HttpService:JSONDecode((table.concat(concatTbl)))
		return valueBuffer
	end,

	[ZSTD_BASE64_ENCODE_ID] = function(encodedData: string)
		local concatTbl = zstd_base64ConcatTbl
		concatTbl[2] = encodedData

		local valueBuffer = HttpService:JSONDecode((table.concat(concatTbl)))
		return valueBuffer
	end,

	[ZSTD_BASE256_ENCODE_ID] = function(encodedData: string)
		local base64Data = base256ToBase64(encodedData)
		local padding = string.rep("=", (4 - #base64Data % 4) % 4)

		local concatTbl = zstd_base256ConcatTbl
		concatTbl[2] = base64Data
		concatTbl[3] = padding

		local valueBuffer = HttpService:JSONDecode((table.concat(concatTbl)))
		return valueBuffer
	end,

	[SPLIT_BASE256_ENCODE_ID] = function(encodedData: string)
		-- Format: {encodedType}{bufferAmount}{buffer1Type}{buffer1Data}{buffer2Type}{buffer2Data}...
		local bufferAmount = string.byte(string.sub(encodedData, 1, 1))
		local lastDataLengthBytes = string.sub(encodedData, bufferAmount * 4 - 2, bufferAmount * 4 + 1)
		local lastDataLength = unpackU32(lastDataLengthBytes)

		local lastBufferData = string.sub(encodedData, -lastDataLength)
		local lastBufferEncodeType = string.sub(encodedData, -lastDataLength - 1, -lastDataLength - 1)
		local lastBufferBase64Data = base256ToBase64(lastBufferData)
		local lastBufferPadding = string.rep("=", (4 - #lastBufferBase64Data % 4) % 4)

		local lastBufferConcatTbl = if lastBufferEncodeType == BASE256_ENCODE_ID
			then base256ConcatTbl
			else zstd_base256ConcatTbl

		lastBufferConcatTbl[2] = lastBufferBase64Data
		lastBufferConcatTbl[3] = lastBufferPadding
		local lastBuffer = HttpService:JSONDecode((table.concat(lastBufferConcatTbl)))

		-- Calculate total buffer size needed
		local lastBufferSize = buffer.len(lastBuffer)
		local totalSize = (bufferAmount - 1) * JSON_ENCODE_MAX_SIZE + lastBufferSize

		-- Create the final buffer and copy all chunks
		local resultBuffer = buffer.create(totalSize)
		buffer.copy(resultBuffer, (bufferAmount - 1) * JSON_ENCODE_MAX_SIZE, lastBuffer)
		lastBuffer = nil

		local dataCursor = bufferAmount * 4 + 2
		for i = 1, bufferAmount - 1 do
			local lengthCursor = i * 4 - 2
			local lengthBytes = string.sub(encodedData, lengthCursor, lengthCursor + 3)
			local dataLength = unpackU32(lengthBytes)

			local bufferEncodeType = string.sub(encodedData, dataCursor, dataCursor)
			local bufferData = string.sub(encodedData, dataCursor + 1, dataCursor + dataLength)
			dataCursor += dataLength + 1

			local bufferBase64Data = base256ToBase64(bufferData)
			local padding = string.rep("=", (4 - #bufferBase64Data % 4) % 4)

			local bufferConcatTbl = if bufferEncodeType == BASE256_ENCODE_ID
				then base256ConcatTbl
				else zstd_base256ConcatTbl

			bufferConcatTbl[2] = bufferBase64Data
			bufferConcatTbl[3] = padding

			local dataBuffer = HttpService:JSONDecode((table.concat(bufferConcatTbl)))
			buffer.copy(resultBuffer, (i - 1) * JSON_ENCODE_MAX_SIZE, dataBuffer)
		end

		return resultBuffer
	end,
}

--[[
	BufferEncoder

	This module encodes buffer data into a string format, selecting the encoding method
	based on the size and structure of the data.

	Encoding Methods:
	- PURE_JSON_ENCODER_ID: Data is stored exactly as returned by `JSONEncode`.
	- STRIP_JSON_ENCODER_ID: Metadata is removed from `JSONEncode` output; result is Base64 encoded.
	- BASE256_JSON_ENCODER_ID: Stripped JSON output is further encoded into Base256.

	Chunking Details:
	- ChunkAmount can be safely stored as a u8 (0–255), which is sufficient given that:
		- Maximum buffer size is 1 GiB (2^30 = 1,073,741,824 bytes).
		- Maximum JSON size is approximately 52,428,800 bytes 
		  (2^25 + 2^24 + 2^21), resulting in a maximum of 20 chunks.

	Note:
	- Some logic is intentionally duplicated for performance reasons,
	  and cannot be refactored into helper functions without incurring overhead.
]]
local BufferEncoder = {
	--// Pure JSON
	[PURE_JSON_ENCODER_ID] = function(valueBuffer: buffer): string
		local bufferSize = buffer.len(valueBuffer)
		if bufferSize > JSON_ENCODE_MAX_SIZE then
			local chunkAmount = math.ceil(bufferSize / JSON_ENCODE_MAX_SIZE)
			local tempBuffer = buffer.create(JSON_ENCODE_MAX_SIZE)
			local leftOver = bufferSize % JSON_ENCODE_MAX_SIZE

			-- The following is expanded for clarity, but it will be constant folded on compilation
			local tblSize = chunkAmount * (
					1 -- buffer data
					+ 1 -- buffer length
				)
				+ 1 -- buffer amount
				+ 1 -- encode id

			--// format: `{encodeType}{bufferAmount}{json1Length}{json2Length}...{buffer1Data}{buffer2Data}...`
			local result = table.create(tblSize)
			result[1] = SPLIT_JSON_ENCODE_ID
			result[2] = string.char(chunkAmount)

			local offset = chunkAmount + 2

			for i = 1, chunkAmount - 1 do
				local start = (i - 1) * JSON_ENCODE_MAX_SIZE

				buffer.copy(tempBuffer, 0, valueBuffer, start, JSON_ENCODE_MAX_SIZE)
				local encodedData = HttpService:JSONEncode(tempBuffer)

				result[i + offset] = encodedData
				result[i + 2] = packU32(#encodedData)
			end

			do
				if leftOver == 0 then leftOver = JSON_ENCODE_MAX_SIZE end
				local start = (chunkAmount - 1) * JSON_ENCODE_MAX_SIZE

				tempBuffer = buffer.create(leftOver)
				buffer.copy(tempBuffer, 0, valueBuffer, start)

				local encodedData = HttpService:JSONEncode(tempBuffer)

				result[tblSize] = encodedData
				result[chunkAmount + 2] = packU32(#encodedData)
			end

			assert(#result == tblSize, "Buffer size mismatch")
			return table.concat(result)
		else
			return HttpService:JSONEncode(valueBuffer)
		end
	end,

	--// Stripped JSON
	[STRIP_JSON_ENCODER_ID] = function(valueBuffer: buffer): string
		local bufferSize = buffer.len(valueBuffer)
		if bufferSize > JSON_ENCODE_MAX_SIZE then
			local chunkAmount = math.ceil(bufferSize / JSON_ENCODE_MAX_SIZE)
			local tempBuffer = buffer.create(JSON_ENCODE_MAX_SIZE)
			local leftOver = bufferSize % JSON_ENCODE_MAX_SIZE

			-- The following is expanded for clarity, but it will be constant folded on compilation
			local tblSize = chunkAmount
					* (
						1 -- 1 index per buffer for buffer length
						+ 1 -- 1 index per buffer for encode type
						+ 1 -- 1 index per buffer for base64 data
					)
				+ 1 -- 1 index for encode type
				+ 1 -- 1 index for buffer amount

			--// format: `{encodeType}{bufferAmount}{encodedData1Length}{encodedData2Length}...{encodedData1Data}{encodedData2Data}...`
			local result = table.create(tblSize)
			result[1] = SPLIT_BASE64_ENCODE_ID
			result[2] = string.char(chunkAmount)

			local offset = chunkAmount + 1

			for i = 1, chunkAmount - 1 do
				local start = (i - 1) * JSON_ENCODE_MAX_SIZE
				buffer.copy(tempBuffer, 0, valueBuffer, start, JSON_ENCODE_MAX_SIZE)

				local encodedData = HttpService:JSONEncode(tempBuffer)
				local base64Data

				if string.sub(encodedData, BASE_METADATA_OFFSET, BASE_METADATA_OFFSET + 5) == "base64" then
					base64Data = string.sub(encodedData, BASE64_DATA_START_OFFSET, BASE64_DATA_END_OFFSET)
					result[i * 2 + offset] = BASE64_ENCODE_ID
				else
					base64Data = string.sub(encodedData, ZSTD_BASE64_DATA_START_OFFSET, ZSTD_BASE64_DATA_END_OFFSET)
					result[i * 2 + offset] = ZSTD_BASE64_ENCODE_ID
				end

				result[i * 2 + offset + 1] = base64Data
				result[i + 2] = packU32(#base64Data)
			end

			do
				if leftOver == 0 then leftOver = JSON_ENCODE_MAX_SIZE end
				local start = (chunkAmount - 1) * JSON_ENCODE_MAX_SIZE

				tempBuffer = buffer.create(leftOver)
				buffer.copy(tempBuffer, 0, valueBuffer, start)

				local encodedData = HttpService:JSONEncode(tempBuffer)
				local base64Data

				if string.sub(encodedData, BASE_METADATA_OFFSET, BASE_METADATA_OFFSET + 5) == "base64" then
					base64Data = string.sub(encodedData, BASE64_DATA_START_OFFSET, BASE64_DATA_END_OFFSET)
					result[tblSize - 1] = BASE64_ENCODE_ID
				else
					base64Data = string.sub(encodedData, ZSTD_BASE64_DATA_START_OFFSET, ZSTD_BASE64_DATA_END_OFFSET)
					result[tblSize - 1] = ZSTD_BASE64_ENCODE_ID
				end

				result[tblSize] = base64Data
				result[chunkAmount + 2] = packU32(#base64Data)
			end

			assert(#result == tblSize, "Buffer size mismatch")
			return table.concat(result)
		else
			local JSON = HttpService:JSONEncode(valueBuffer)

			if string.sub(JSON, BASE_METADATA_OFFSET, BASE_METADATA_OFFSET + 5) == "base64" then
				local base64Data = string.sub(JSON, BASE64_DATA_START_OFFSET, BASE64_DATA_END_OFFSET)
				return BASE64_ENCODE_ID .. base64Data
			else
				local base64Data = string.sub(JSON, ZSTD_BASE64_DATA_START_OFFSET, ZSTD_BASE64_DATA_END_OFFSET)
				return ZSTD_BASE64_ENCODE_ID .. base64Data
			end
		end
	end,

	--// Encoded JSON
	[BASE256_JSON_ENCODER_ID] = function(valueBuffer: buffer): string
		local bufferSize = buffer.len(valueBuffer)
		if bufferSize > JSON_ENCODE_MAX_SIZE then
			local chunkAmount = math.ceil(bufferSize / JSON_ENCODE_MAX_SIZE)
			local tempBuffer = buffer.create(JSON_ENCODE_MAX_SIZE)
			local leftOver = bufferSize % JSON_ENCODE_MAX_SIZE

			-- The following is expanded for clarity, but it will be constant folded on compilation
			local tblSize = chunkAmount
					* (
						1 -- 1 index per buffer for buffer length
						+ 1 -- 1 index per buffer for encode type
						+ 1 -- 1 index per buffer for base256 data
					)
				+ 1 -- 1 index for encode type
				+ 1 -- 1 index for buffer amount

			--// format: `{encodeType}{bufferAmount}{encodedData1Length}{encodedData2Length}...{encodedData1Data}{encodedData2Data}...`
			local result = table.create(tblSize)
			result[1] = SPLIT_BASE256_ENCODE_ID
			result[2] = string.char(chunkAmount)

			local offset = chunkAmount + 1

			for i = 1, chunkAmount - 1 do
				local start = (i - 1) * JSON_ENCODE_MAX_SIZE
				buffer.copy(tempBuffer, 0, valueBuffer, start, JSON_ENCODE_MAX_SIZE)

				local encodedData = HttpService:JSONEncode(tempBuffer)
				local base256Data

				local lastBase64Char = -3
				local lastChar = string.sub(encodedData, -3, -3)

				if lastChar == "=" then
					local secondLastChar = string.sub(encodedData, -4, -4)
					if secondLastChar == "=" then
						lastBase64Char = -5
					else
						lastBase64Char = -4
					end
				end

				if string.sub(encodedData, BASE_METADATA_OFFSET, BASE_METADATA_OFFSET + 5) == "base64" then
					base256Data = base64ToBase256(string.sub(encodedData, 34, lastBase64Char))
					result[i * 2 + offset] = BASE256_ENCODE_ID
				else
					base256Data = base64ToBase256(string.sub(encodedData, 35, lastBase64Char))
					result[i * 2 + offset] = ZSTD_BASE256_ENCODE_ID
				end

				result[i * 2 + offset + 1] = base256Data
				result[i + 2] = packU32(#base256Data)
			end

			do
				local start = (chunkAmount - 1) * JSON_ENCODE_MAX_SIZE
				local lastBuffer = buffer.create(leftOver)
				buffer.copy(lastBuffer, 0, valueBuffer, start)

				local encodedData = HttpService:JSONEncode(lastBuffer)
				local base256Data

				local lastBase64Char = -3
				local lastChar = string.sub(encodedData, -3, -3)

				if lastChar == "=" then
					local secondLastChar = string.sub(encodedData, -4, -4)
					if secondLastChar == "=" then
						lastBase64Char = -5
					else
						lastBase64Char = -4
					end
				end

				if string.sub(encodedData, BASE_METADATA_OFFSET, BASE_METADATA_OFFSET + 5) == "base64" then
					base256Data = base64ToBase256(string.sub(encodedData, 34, lastBase64Char))
					result[tblSize - 1] = BASE256_ENCODE_ID
				else
					base256Data = base64ToBase256(string.sub(encodedData, 35, lastBase64Char))
					result[tblSize - 1] = ZSTD_BASE256_ENCODE_ID
				end

				result[tblSize] = base256Data
				result[chunkAmount + 2] = packU32(#base256Data)
			end

			return table.concat(result)
		else
			local JSON = HttpService:JSONEncode(valueBuffer)

			local lastBase64Char = -3
			local lastChar = string.sub(JSON, -3, -3)

			-- Fragile logic for padding detection
			-- Must be changed if the JSONEncode format changes
			if lastChar == "=" then
				local secondLastChar = string.sub(JSON, -4, -4)
				if secondLastChar == "=" then
					lastBase64Char = -5
				else
					lastBase64Char = -4
				end
			end

			if string.sub(JSON, BASE_METADATA_OFFSET, BASE_METADATA_OFFSET + 5) == "base64" then
				local base64Data = string.sub(JSON, 34, lastBase64Char)
				return BASE256_ENCODE_ID .. base64ToBase256(base64Data)
			else
				local base64Data = string.sub(JSON, 35, lastBase64Char)
				return ZSTD_BASE256_ENCODE_ID .. base64ToBase256(base64Data)
			end
		end
	end,
}

--[[
	The buffer scheme is currently the same across levels of compressors,
	but they are modularized into multiple functions for future flexibility.
	Buffer scheme may vary across different compression levels in the future.
]]
local Compressor = {

	[1] = function<input>(value: input): string
		local totalSize = getSize(value)
		if totalSize > BUFFER_MAX_SIZE then error("Value size exceeds buffer limit", 3) end

		local valueBuffer = buffer.create(totalSize)
		writeValue(valueBuffer, 0, value)

		return BufferEncoder[PURE_JSON_ENCODER_ID](valueBuffer)
	end,

	[2] = function<input>(value: input): string
		local totalSize = getSize(value)
		if totalSize > BUFFER_MAX_SIZE then error("Value size exceeds buffer limit", 3) end

		local valueBuffer = buffer.create(totalSize)
		writeValue(valueBuffer, 0, value)

		return BufferEncoder[STRIP_JSON_ENCODER_ID](valueBuffer)
	end,

	[3] = function<input>(value: input): string
		local totalSize = getSize(value)
		if totalSize > BUFFER_MAX_SIZE then error("Value size exceeds buffer limit", 3) end

		local valueBuffer = buffer.create(totalSize)
		writeValue(valueBuffer, 0, value)

		return BufferEncoder[BASE256_JSON_ENCODER_ID](valueBuffer)
	end,
}

--//

--[=[

    Compresses the given input value using the specified compression level.

    If the input `value` is `nil`, this function will return an empty string.
    The `level` parameter dictates the compression algorithm used. If an invalid
    compression level is provided, the function will error.

    @param value: `any` - The value to be compressed. Can be of any type.
    @param level: `number` - The compression level to use. Must correspond to a defined compressor.
    @return string: `string` - The compressed string representation of the input value.

]=]
local function compress<input>(value: input, level: number): string
	if value == nil then return "" end
	local compressFunc = Compressor[level]
	if not compressFunc then error(`Invalid compression level {level}`, 2) end
	return (compressFunc(value))
end

--[=[

    Decompresses a previously compressed string back into its original Luau value.

    If the input `value` is an empty string, this function will return `nil`.
    The function automatically determines the compression/encoding type by inspecting
    the first character (prefix) of the input string.

    If no known prefix is identified, it will attempt to directly decode the string
    as a JSON-encoded value as a fallback mechanism. If this fallback also fails,
    or if an invalid compression type (based on the prefix) is encountered,
    the function will error.

    @param value: `string` - The compressed string to be decompressed.
    @return output: `any` - The original, decompressed Luau value. The type will match the original input to the `compress` function.

]=]
local function decompress<output>(value: string): output
	if value == "" then return nil :: any end
	local compressType = string.sub(value, 1, 1)
	local decodeFunc = BufferDecoder[compressType]

	if not decodeFunc then
		local success, result = pcall(HttpService.JSONDecode, HttpService, value)
		if success then return (deserializeValue(result, 0)) end

		error(`Invalid compression type {compressType}`, 2)
	end

	local compressedData = string.sub(value, 2)
	local valueBuffer = decodeFunc(compressedData)

	return (deserializeValue(valueBuffer, 0))
end

--// Integrity Checks

--[[
	These checks run when the module is loaded to verify that the underlying
	HttpService:JSONEncode format for buffers hasn't changed, as this module
	relies on that specific format for stripping metadata.
]]

do
	-- Check encoding of an empty buffer (should use "base64").
	local emptyBuffer = buffer.create(0)
	local JSON = HttpService:JSONEncode(emptyBuffer)

	assert(JSON == [[{"m":null,"t":"buffer","base64":""}]], "Invalid JSON encoding, format changed")
end

do
	-- Check encoding of a small buffer that HttpService will compress with ZSTD (using "zbase64").
	-- The size 19 is the smallest size that will be compressed with ZSTD.
	local compressionBuffer = buffer.create(19)
	local JSON = HttpService:JSONEncode(compressionBuffer)

	assert(
		JSON == [[{"m":null,"t":"buffer","zbase64":"KLUv/SATRQAAEAAAAQAzwAI="}]],
		"Invalid JSON encoding, format changed"
	)
end

--// Return \\--

return {
	ConvertToBuffer = function<input>(value: input): buffer
		local totalSize = getSize(value)
		if totalSize > BUFFER_MAX_SIZE then error("Value size exceeds buffer limit", 3) end

		local valueBuffer = buffer.create(totalSize)
		writeValue(valueBuffer, 0, value)

		return valueBuffer
	end,
	Compress = compress,
	Decompress = decompress,
}
