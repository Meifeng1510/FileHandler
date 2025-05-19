--!strict
--[[
	Roblox Plugin File Handler Utility
	----------------------------------
	Author: @meifeng_ft
	Date: 2025-05-19 (Last Updated)

	Description:
	This module provides a suite of functions for handling file operations
	within a Roblox Studio plugin environment. It simplifies tasks such as
	prompting users to import or export files, managing text content, and
	integrating with compression utilities.

	Features:
	- User prompts for file import (generic files, text files).
	- User prompts for file export (Instances, text content).
	- Integration with a `Compressor` module for data compression/decompression.
	- Helper functions for combined operations like importing compressed values
	  or exporting compressed values.
	- Basic error handling for file operations and compression/decompression.

	Dependencies:
	- `Compressor` module (expected to be in the same directory).
	- Requires a `Plugin` instance to be set via `SetPlugin()` for export operations
	  that use `plugin:PromptSaveSelection()`.

	Important Notes:
	- Ensure `FileHandler.SetPlugin(pluginInstance)` is called before attempting
	  any export operations.
	- File import functions (`PromptImportFile`, `PromptImportText`, `PromptImportCompressedValue`)
	  return `nil` if the user cancels the prompt or an error occurs.
	- Export functions for text content (`PromptExportText`, `PromptExportValueCompressed`)
	  temporarily create a `ModuleScript` instance to leverage `plugin:PromptSaveSelection()`.
	  The default file extension for these operations will be `.lua`.
]]
--// Types \\--

--// Services \\--

local SelectionService = game:GetService("Selection")
local StudioService = game:GetService("StudioService")
local ScriptEditorService = game:GetService("ScriptEditorService")

--// Modules \\--

-- Assuming Compressor.luau is in the same directory as this init.luau (src/FileHandler/)
local Compressor = require(script.Compressor)

--// Variables \\--

local plugin: Plugin

--// Class \\--

--[[
	FileHandler

	A utility module for handling file operations within a Roblox plugin,
	including importing, exporting, compressing, and decompressing data.
]]
local FileHandler = {}

--// Private Functions \\--

--// Functions \\--

--[[
	SetPlugin

	Sets the plugin instance for the FileHandler to use for operations
	that require plugin-specific functionality (e.g., PromptSaveSelection).

	@param pluginInstance (Plugin): The active plugin instance.
]]
function FileHandler.SetPlugin(pluginInstance: Plugin): ()
	plugin = pluginInstance
end

--[[
	CompressValue

	Compresses the given Luau value into a string.

	@param content (any): The Luau value to compress.
	@param level (number): The compression level.
	@return (string): The compressed string representation of the content.
]]
function FileHandler.CompressValue<input>(content: input, level: number): string
	return Compressor.Compress(content, level)
end

--[[
	DecompressValue

	Decompresses a string (previously compressed by CompressValue) back into
	its original Luau value.

	@param content (string): The compressed string.
	@return (any): The decompressed Luau value.
]]
function FileHandler.DecompressValue<result>(content: string): result
	return Compressor.Decompress(content)
end

--[[
	PromptImportFile

	Prompts the user to select a file for import.

	@param fileTypeFilter ({string}): A table of file extensions to filter by (e.g., {"json", "txt"}).
	@return (File?): The selected File object, or nil if the user cancels.
]]
function FileHandler.PromptImportFile(fileTypeFilter: { string }): File?
	local file = StudioService:PromptImportFile(fileTypeFilter)
	return file
end

--[[
	PromptExportFile

	Prompts the user to save the given Instance to a file.

	@param fileName (string): The default file name (without extension).
	@param object (Instance): The Roblox Instance to export.
	@return (boolean): True if the export was successful, false otherwise.
]]
function FileHandler.PromptExportFile(fileName: string, object: Instance): boolean
	if not plugin then
		error("Plugin not set. Call FileHandler.SetPlugin(pluginInstance) first.", 2)
	end
	SelectionService:Set({ object })

	local success = plugin:PromptSaveSelection(fileName)
	return success
end

--[[
	PromptImportText

	Prompts the user to select a file and reads its content as a string.

	@param fileTypeFilter ({string}?): Optional. A table of file extensions to filter by.
	@return (string?): The content of the file as a string, or nil if the user
	                  cancels or the file cannot be read.
]]
function FileHandler.PromptImportText(fileTypeFilter: { string }?): string?
	local file = StudioService:PromptImportFile(fileTypeFilter)
	if not file then
		return nil
	end
	return file:GetBinaryContents()
end

--[[
	PromptExportText

	Prompts the user to save the given text to a file.

	@param fileName (string): The default file name (without extension, .lua will be added).
	@param text (string): The text content to export.
	@return (boolean): True if the export was successful, false otherwise.
]]
function FileHandler.PromptExportText(fileName: string, text: string): boolean
	if not plugin then
		error("Plugin not set. Call FileHandler.SetPlugin(pluginInstance) first.", 2)
	end
	local textScript = Instance.new("ModuleScript")
	-- Roblox Studio automatically appends .lua to the filename for ModuleScripts
	-- when using PromptSaveSelection. If a different extension is desired
	local successUpdateSource, err = ScriptEditorService:UpdateSourceAsync(textScript, function()
		return text
	end)

	if not successUpdateSource then
		warn("FileHandler.PromptExportText: Failed to update temporary script source:", err)
		textScript:Destroy()
		return false
	end

	textScript.Parent = workspace -- Needs a temporary parent for selection

	SelectionService:Set({ textScript })
	local successSave = plugin:PromptSaveSelection(fileName)

	textScript:Destroy()
	return successSave
end

--[[
	PromptImportCompressedValue

	Prompts the user to select a file, reads its content,
	and decompresses it into a Luau value.

	@param fileTypeFilter ({string}?): Optional. A table of file extensions to filter by.
	@return (boolean, any): A success flag and either the decompressed Luau value or the error message.
]]
function FileHandler.PromptImportCompressedValue<result>(fileTypeFilter: { string }?): (boolean, result?)
	local content = FileHandler.PromptImportText(fileTypeFilter)
	if not content then
		return false, "No content or user canceled" :: any
	end

	local success, value = pcall(Compressor.Decompress, content)
	if not success then
		return false, `FileHandler.PromptImportCompressedValue: Failed to decompress content - {value}` :: any
	end

	return true, value
end

--[[
	PromptExportValueCompressed

	Compresses the given Luau value and prompts the user to save it to a file.

	@param fileName (string): The default file name (without extension).
	@param content (any): The Luau value to compress and export.
	@param level (number): The compression level.
	@return (boolean): True if the export was successful, false otherwise.
]]
function FileHandler.PromptExportValueCompressed<input>(fileName: string, content: input, level: number): boolean
	if not plugin then
		error("Plugin not set. Call FileHandler.SetPlugin(pluginInstance) first.", 2)
	end
	local successCompress, compressedValue = pcall(Compressor.Compress, content, level)
	if not successCompress then
		warn("FileHandler.PromptExportValueCompressed: Failed to compress content - ", compressedValue) -- 'compressedValue' here is the error message
		return false
	end
	return FileHandler.PromptExportText(fileName, compressedValue :: string)
end

--// Return \\--

return FileHandler
