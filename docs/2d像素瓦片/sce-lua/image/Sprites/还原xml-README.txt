SpriteSheet2D 帧定义文件（.xml）上传说明
==========================================

问题：SCE / 星火 资源上传工具不接受 .xml 后缀的文件，无法直接上传。

本目录里每个精灵表都给了两份：
  <name>.xml        —— 运行时 Lua 真正引用的文件（image/Sprites/<name>.xml）。
                       如果你是直接把整个工程拷进引擎目录，这份已经可用，无需理会下面。
  <name>_xml.jpg    —— 同内容的上传友好副本（其实是 XML 文本，仅后缀改成 .jpg 以通过上传）。

若必须经上传工具：
  1) 上传所有 <name>_xml.jpg 到目标工程的 image/Sprites/ 目录；
  2) 上传后把每个 <name>_xml.jpg 改名回 <name>.xml（去掉结尾的 _xml.jpg，加回 .xml）；
     例：wizard_idle_xml.jpg  ->  wizard_idle.xml
  3) 也可运行本目录的 restore-xml.bat（Windows）/ restore-xml.sh（macOS/Linux）批量还原。

注意：运行时 Lua 用 cache:GetResource("SpriteSheet2D", "image/Sprites/<name>.xml") 加载，
      文件名必须最终是 .xml，否则精灵表加载失败、角色/敌人/瓦片只显示占位或不可见。
