# 换行符与「只看对方改了什么」

> 从建模项目的跨平台协作笔记里抽出来的通用部分。场景是：协作者在 Windows 上工作，你在 WSL/Linux 上合并他们的改动。

---

## 问题

Windows 上编辑过的文件带 CRLF 行尾，Linux 上是 LF。直接 diff 会把**整个文件报成重写**，于是「只看对方改了什么」这件事彻底失效——真正的几行改动淹没在几百行假 diff 里。

## 走 Git 的情况：`.gitattributes` 能挡住

仓库根放一个 `.gitattributes`，统一入库时的行尾：

```gitattributes
* text=auto
*.sh   text eol=lf
*.ps1  text eol=crlf
*.bat  text eol=crlf
```

`text=auto` 让 Git 在入库时把文本文件统一成 LF，检出时按平台还原。这样 Windows 协作者提交的内容在库里始终是 LF，diff 干净。

## ⚠️ 不走 Git 的情况：`.gitattributes` 不生效

**这是最容易栽的地方。** 协作者有时是用**目录拷贝或 zip** 把改动交回来的——完全没经过 Git，`.gitattributes` 无从介入，CRLF 原样落到你的工作区。

这时 diff 必须显式忽略行尾差异：

```bash
diff -r --strip-trailing-cr old_dir/ new_dir/
git diff --ignore-cr-at-eol                    # 已在工作区里的话
```

不加这个参数，你会看到整个文件被标成改动，然后花半小时找"对方到底改了啥"。

## 判断文件当前是什么行尾

```bash
file somefile.py                    # 会说 "with CRLF line terminators"
grep -c $'\r' somefile.py           # 数带 CR 的行
```

批量转换：

```bash
sed -i 's/\r$//' file               # CRLF -> LF
dos2unix file                       # 同上，需要装 dos2unix
```

## 顺带：路径也别硬编码

三台机器（Windows 的 `E:/...`、WSL 的 `~/code/...`、云端的 `/data/...`）意味着：

- **文档里一律用仓库相对路径**，复现命令写成从仓库根起的 `cd <subdir>`
- 引用位置用 `文件:行号` 形式，跨平台通用
- **代码里不要硬编码任一平台的路径**——最典型的是字体路径，见 [`../agent/skills/wsl-cjk-font/`](../agent/skills/wsl-cjk-font/)

---

## 相关

- [`README.md`](README.md) —— GitHub 隐私邮箱、gh 登录与凭据、代理调优
- [`email-scrub-runbook.md`](email-scrub-runbook.md) —— 清洗历史里的真实邮箱
