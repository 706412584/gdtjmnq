# 默认项目 SCE Lua Export

This folder targets TapTap / SCE / UrhoX Lua UI projects.

Copy `sce-lua/scripts/` into the target project's `scripts/` directory.
Copy `sce-lua/image/` into the target project's resource/image directory.
The generated `main.lua` auto-loads the first exported page from `ui_registry.lua`.
Generated `ui_xxx.lua` modules are self-contained and do not require `rich_text.lua`.
2D gameplay scenes are exported as native UrhoX 2D scenes (`scene2d_*.lua` + `logic_*.lua`), with sprite sheets under `image/Sprites/`.
注意：SCE 资源上传工具不接受 .xml 后缀。精灵表 (`image/Sprites/<name>.xml`) 同时提供了上传友好副本 `<name>_xml.jpg`（内容仍是 XML）；经上传通道后需改名回 `.xml`（见 `image/Sprites/还原xml-README.txt` 或运行 `restore-xml.bat`/`restore-xml.sh`）。直接拷贝整个工程则无需处理。
