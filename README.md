# DataAutoBackupTool

数据自动备份工具 - 基于 MySQL 的数据库与图片文件备份与恢复系统

## 功能特性

- 数据库表结构导出/导入 (Schema)
- 数据库数据备份与恢复 (Data) - 按 GUID 分区管理
- 图片文件自动备份 (基于 robocopy)
- 重复数据处理策略 (跳过 / 覆盖 / 追加)
- 数据库连接测试与配置
- 自动定时备份 (Windows 任务计划 + 自动运行开关)
- 备份操作记录与日志
- 图形化操作界面 (WinForms)

## 技术栈

- 前端 GUI: .NET Framework 4.8 + WinForms (C#)
- 脚本引擎: PowerShell 5.x
- 数据库: MySQL 8.0 (mysqldump)
- JSON 处理: Newtonsoft.Json 13.0.3
- 文件复制: robocopy (Windows 内置)

## 项目结构

`
repos/
+-- WindowsApplication.exe      主程序（图形界面入口，编译产物）
+-- StandaloneApp.cs            GUI 源码（C# WinForms）
+-- export.csproj               .NET 项目文件
|
+-- AutoBackup.ps1              自动备份入口脚本
+-- schema.ps1                  表结构备份 (mysqldump --no-data)
+-- GUID-Data.ps1               按 GUID 导出表数据
+-- ImportWork.ps1              数据导入与恢复（含重复处理）
+-- imagecopy.ps1               图片文件备份（robocopy）
+-- DeleteData.ps1              删除指定 GUID 的数据
+-- DeleteBackup.ps1            清理过期备份
|
+-- config.json                 用户配置（含密码，不提交）
+-- config.example.json          配置示例模板（可提交）
+-- Newtonsoft.Json.dll         JSON 库
+-- .gitignore                  Git 忽略规则
|
+-- data/                       数据备份输出目录 (GUID 分区)
+-- schema/                     表结构备份输出目录
+-- Records/                    操作记录与日志
`

## 快速开始

### 1. 环境要求

- Windows 7 / 10 / 11（推荐 Win10 及以上）
- .NET Framework 4.8（Win10/11 通常已预装）
- PowerShell 5.0 及以上
- MySQL Server 8.0（含 mysqldump 工具）
- MySQL 安装路径需在以下任一位置：
  - C:\Program Files\MySQL\MySQL Server 8.0\bin
  - D:\MySQL\MySQL Server 8.0\bin
  - E:\MySQL\MySQL Server 8.0\bin

### 2. 配置数据库

将 config.example.json 复制为 config.json，然后填入你的实际配置：

`json
{
    "backupMysql": {
        "host": "127.0.0.1",
        "port": "3306",
        "user": "root",
        "password": "your_password",
        "database": "your_backup_database"
    },
    "importMysql": {
        "host": "127.0.0.1",
        "port": "3306",
        "user": "root",
        "password": "your_password",
        "database": "your_target_database"
    },
    "paths": {
        "baseTargetPath": ".",
        "schemaOutputPath": ".",
        "dataBackupPath": "data",
        "imageBackupPath": "vtImages_2D/images",
        "schemaBackupPath": "."
    },
    "saveImgPath": {
        "module_name": "D:\\path\\to\\images"
    }
}
`

### 3. 启动应用

直接双击 WindowsApplication.exe，或在 PowerShell 中：

`powershell
cd repos
.\WindowsApplication.exe
`

## 从源码编译

```powershell
# 使用 MSBuild (.NET Framework 4.8)
MSBuild export.csproj /t:Build /p:Configuration=Release /p:Platform=x86

# 或在项目目录直接使用自带 MSBuild：
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\MSBuild.exe export.csproj /t:Build /p:Configuration=Release /p:Platform=x86
```

编译输出：WindowsApplication.exe（项目根目录）

## 自动定时备份

在 GUI 的"自动备份"区域设置执行时间，勾选"启用自动备份"并保存配置，系统将自动创建 Windows 计划任务。

**工作原理**：GUI → Windows 任务计划程序 → 每日指定时间执行 `WindowsApplication.exe -auto` → 静默运行 `AutoBackup.ps1` → 按 GUID 执行数据/图片/表结构备份。

**手动删除任务**：在 GUI 中取消勾选"启用自动备份"并保存，系统将自动移除任务；也可在 PowerShell 中执行：`schtasks /Delete /TN "DataBackupTool_AutoBackup" /F`

## 核心脚本说明

| 脚本 | 功能 | 输入参数 |
|------|------|---------|
| schema.ps1 | 导出所有表结构到 SQL 文件 | -guid, -path |
| GUID-Data.ps1 | 按 GUID 条件导出表数据 | -guid, -path |
| ImportWork.ps1 | 导入 SQL 文件到目标数据库（含重复策略） | -path, -strategy 等 |
| imagecopy.ps1 | 备份图片文件 | -source, -target |
| AutoBackup.ps1 | 一键执行完整备份流程 | 通过图形化界面配置 |
| DeleteData.ps1 | 按 GUID 删除数据库数据 | -guid |
| DeleteBackup.ps1 | 清理旧备份文件 | 天数阈值 |

## 注意事项

1. **备份与导入数据库分离**：config.json 中 backupMysql 和 importMysql 是两个独立的数据库连接配置，支持跨服务器数据迁移。
2. **MySQL 路径自动检测**：脚本会依次检查 C:\、D:\、E:\ 盘的 MySQL 安装目录，并在 PATH 环境变量中搜索。
3. **GUID 分区管理**：所有数据备份/恢复都通过 GUID 标识隔离，便于按批次管理。
4. **安全提醒**：config.json 包含数据库密码，已加入 .gitignore，**切勿**提交到公开仓库。
5. **命令行安全**：所有 MySQL 客户端调用均直接通过 `ProcessStartInfo` 启动 mysql.exe，不经过 `cmd.exe` 外壳，避免命令注入风险。
6. **文件编码**：所有脚本与源码均以 UTF-8（带 BOM）保存，确保跨系统中文兼容性。

## License

MIT License