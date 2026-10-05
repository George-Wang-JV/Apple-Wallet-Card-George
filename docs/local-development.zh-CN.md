# 本地开发与 GitHub 同步

这份分支增加了本地卡面库和每张卡的历史记录，移除了捐赠界面，并将底部署名改为 George & Luna。原始 MIT LICENSE 保留，并随构建复制到应用资源目录。

## 使用卡面库

- 顶部 **Skin Library → Import Images…**：一次导入多张图片。无须连接手机。
- 点击卡片或悬停后选择 **Change Skin**：从库中选择，或导入新图片后点击 **Use Skin**。
- 悬停后选择 **Skin History**：查看这张卡在当前 iPhone 上曾分配过的卡面，点击 **Use Skin** 切换。右键菜单也有这两个入口。
- 历史记录包括已选择、尚未写入手机的卡面；切换只改变本地预览。点击 **Flash Skins** 才写入手机。
- 拖入卡片的图片，以及批量指定的图片，也会保存到库中。同一图片重复导入会去重。
- 图片副本与索引保存在 `~/Library/Application Support/AirCard/SkinLibrary/`，原图移动或删除不影响复用。此目录不在 Git 仓库中，不会随 push 上传。
- 卡面库初始为空。这是本地个人图库，不自带银行或社区卡面，也不提供云同步。

## 编辑和删除卡面

打开 **Skin Library → Edit**，点击图片下面的 **Delete**，确认后移到 Mac 废纸篓，并从所有卡面历史中移除。原始导入图片和 iPhone 上的卡面不会改变。

仍被任何已保存卡片使用的图片显示 **In Use**：先清除或更换那张卡的卡面，再删除。改名后保留旧版数据目录及设置标识，已有图片和卡片可继续使用。

## 开发版构建

在 Screen 仓库目录执行：

```sh
bash build.sh --dev
open build/Screen.app
```

`--dev` 编译当前 Mac 架构的 Swift 调试版本并跳过 DMG；设备辅助程序仍是通用版本。修改后先退出旧应用，再重新构建和打开。需要 macOS 14+、可用的 Apple Command Line Tools/SDK 和 Python 3。

不带 `--dev` 则保留上游的通用应用和 DMG 构建流程。如果系统开发工具残留重复的 SwiftBridging 模块定义，脚本会生成仅用于本次编译的文件映射，不修改系统目录。缓存和映射保存在被 Git 忽略的 `.tmp/`。

完成一次开发构建后，可运行针对卡面持久化、设备隔离及列表绑定的检查：

```sh
python3 -m unittest discover -s tests -p 'test_wallet_discovery.py'
python3 -m unittest discover -s tests -p 'test_wallet_card_bindings.py'
```

## 第一次推送到自己的 GitHub

开发分支为 `feature/skin-library`。此工作副本的 `origin` 指向 `George-Wang-JV/Apple-Wallet-Card-George`，`upstream` 保留为 `Mak5er/AirCard`。下方首次配置命令仅用于尚未配置 remote 的工作副本；现有工作副本无需重复执行。

1. 打开 <https://github.com/Mak5er/AirCard>，点击 **Fork**，在自己的账户创建副本。
2. 在本地仓库内，执行下面的命令；下面已使用你的 Fork 地址；其他使用者请换成自己的 Fork。重命名 remote 只需做一次。

```sh
git remote rename origin upstream
git remote add origin https://github.com/George-Wang-JV/Apple-Wallet-Card-George.git
git remote -v
git status
git add ScreenApp.swift Sources/SkinLibrary.swift build.sh README.md docs/local-development.zh-CN.md tests/test_wallet_viewmodel.swift tests/test_wallet_discovery.py tests/test_wallet_card_bindings.py
git commit -m "Add local skin library and per-card history; remove donation UI"
git push -u origin feature/skin-library
```

GitHub 身份验证可用 GitHub CLI 的 `gh auth login` 配合 `gh auth setup-git`（已安装 CLI 时），或配置 SSH key 后使用 SSH remote。不要将账户密码或 token 写进代码/remote URL，也不要发送到聊天里。

这会推送到自己的 Fork；无需向原作者提交 PR。后续每次修改、验证后，使用 `git add <具体文件>`、`git commit -m "说明"`、`git push`。

## 在另一台电脑或远程 Mac 上继续

首次在另一台 Mac 克隆自己的分支：

```sh
git clone --branch feature/skin-library https://github.com/George-Wang-JV/Apple-Wallet-Card-George.git
cd Apple-Wallet-Card-George
bash build.sh --dev
open build/Screen.app
```

之后开始修改前，在工作区没有未提交改动时先 `git pull --ff-only`，完成后 commit/push。另一台 Mac 再 pull 并重新构建即可。云端 Linux 编辑器可以改代码，但 SwiftUI 应用的构建和运行仍需要 Mac；USB 扫卡需要手机连接到运行应用的那台 Mac。

参考：[GitHub Fork 与推送流程](https://docs.github.com/en/get-started/exploring-projects-on-github/contributing-to-a-project)、[GitHub SSH 配置](https://docs.github.com/en/authentication/connecting-to-github-with-ssh)。
