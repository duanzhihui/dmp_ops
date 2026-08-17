# 项目运维说明 (AGENTS.md)

本文件记录本仓库的跨平台协作约定与运维要点，供 AI 助手与协作者参考。

## 跨平台文件权限约定 (Windows 提交 / Linux 运行)

### 背景

本仓库在 Windows 端开发提交，在 Linux 端 pull 后运行。由于 NTFS 没有 Unix
可执行位，Windows 端 `git add` 新建的 `.sh` / `.py` / `.pl` / `.service`
等脚本时，git index 中记录的 mode 是 `100644`（不可执行），Linux 端
checkout 后文件权限为 `644`，无法直接 `./xxx.sh` 运行，必须 `bash xxx.sh`
或手动 `chmod +x`。

### 解决方案

git 的可执行位保存在 index 的 mode 字段中，**会随仓库一起传输**。只要在
Windows 端用 `git update-index --chmod=+x` 把 mode 改成 `100755`，Linux
端 pull 下来文件权限自然就是 `755`。

仓库根目录提供了辅助脚本 `git-chmod+x.sh`，可批量处理：

```bash
# 预览将要修改的文件（不实际改动）
bash git-chmod+x.sh --dry-run

# 实际给所有 .sh/.py/.pl/.service 已跟踪文件设置可执行位
bash git-chmod+x.sh

# 只处理某一种扩展名
bash git-chmod+x.sh --ext sh
```

### 标准工作流（Windows 端）

1. 新增脚本文件后，先 `git add <file>` 加入暂存区。
2. 运行 `bash git-chmod+x.sh` 批量给所有脚本设置可执行位。
3. `git commit` 提交。提交内容包含 mode 变更（100644 -> 100755）。
4. `git push`。
5. Linux 端 `git pull` 后，新文件权限即为 755，可直接执行。

### 注意事项

- `.gitattributes` **无法**设置可执行位，只能控制换行符/二进制等属性。
  可执行位必须用 `git update-index --chmod=+x` 设置。
- Windows 工作区文件本身不会显示为可执行（资源管理器无此概念），这是
  正常的；真正的权限信息保存在 git index 中，Linux 端 checkout/pull 时
  才会落地为文件系统权限。
- `git config core.fileMode` 在 Windows 端应为 `false`（默认），这样
  Windows 端不会因为本地权限与 index 不一致而误报文件被修改。
- `systemd` 的 `.service` unit 文件传统上是 644，但本仓库统一设为 755
  以简化流程，systemd 不要求 unit 文件可执行，755 也不会有副作用。

### 换行符约定

Windows 端 `core.autocrlf=true` 时，提交时 CRLF 会被转成 LF 存入仓库，
checkout 时再转回 CRLF。Linux 端默认 `core.autocrlf=false`，checkout 出
来的就是 LF，无需额外处理。**不要**在仓库中提交 CRLF 文件。

## Git 提交信息约定

提交信息使用中文，简明描述"为什么"做这个改动。参考近期 commit 风格。
