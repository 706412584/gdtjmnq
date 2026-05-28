# 古代铁匠模拟器 SCE Lua Export

This folder targets TapTap / SCE / UrhoX Lua UI projects.

Copy `sce-lua/scripts/` into the target project's `scripts/` directory.
Copy `sce-lua/image/` into the target project's resource/image directory.
The generated `main.lua` auto-loads the first exported page from `ui_registry.lua`.
Generated `ui_xxx.lua` modules are self-contained and do not require `rich_text.lua`.
