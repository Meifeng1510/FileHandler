# FileHandler

## Description:
This module provides a suite of functions for handling file operations
within a Roblox Studio plugin environment. It simplifies tasks such as
prompting users to import or export files, managing text content, and
integrating with compression utilities.

 ## Features:
- User prompts for file import (generic files, text files).
- User prompts for file export (Instances, text content).
- Integration with a `Compressor` module for data compression/decompression.
- Helper functions for combined operations like importing compressed values
  or exporting compressed values.
- Basic error handling for file operations and compression/decompression.

 ## Dependencies:
- `Compressor` module (expected to be in the same directory).
- Requires a `Plugin` instance to be set via `SetPlugin()` for export operations
  that use `plugin:PromptSaveSelection()`.

## Important Notes:
- Ensure `FileHandler.SetPlugin(pluginInstance)` is called before attempting
  any export operations.
- Export functions for text content (`PromptExportText`, `PromptExportValueCompressed`)
  temporarily create a `ModuleScript` instance to leverage `plugin:PromptSaveSelection()`.
  The default file extension for these operations will be `.lua`
