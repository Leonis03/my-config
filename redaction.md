# Redaction and portability: how to write a value

*English · [中文（正本 / canonical）](redaction.zh.md) · back to [README](README.md)*

This repo has to satisfy two things that look contradictory: **no real usernames in the
tracked bytes**, and **every path still resolves on whatever machine it is deployed to**. The
method is to classify each value by *how it becomes a real value on the target machine* --
and the test is **whether a shell will expand it**, not what kind of file it appears in.

```
        writing a "name-shaped" value into a tracked file
                              |
                              v
                 +------------------------+
                 | Will a shell expand it? |
                 +-----------+------------+
                  yes       |        no
          +-----------------+        +-------------------+
          v                                              v
 +------------------+                      +--------------------------+
 | (1) runtime var  |                      | Can it be DETECTED on    |
 |                  |                      | the target machine?      |
 | shipped as-is:   |                      +------------+-------------+
 |   $HOME  $USER   |                          yes      |      no
 |                  |              +--------------------+       |
 | expanded by:     |              v                            v
 | the target       |   +-------------------------+  +--------------------+
 | machine's shell  |   | (2) runtime detection   |  | (3) placeholder    |
 |                  |   |                         |  |                    |
 | Linux side only. |   | detection code shipped  |  | shipped as:        |
 | The Windows      |   | as-is:                  |  |   <your-home>      |
 | account name is  |   |  glob /mnt/c/Users/*/   |  |   <your-windows-   |
 | NOT $USER        |   |  %USERPROFILE%+wslpath  |  |    user>           |
 |                  |   |  ~/.cache fallback,     |  |                    |
 |                  |   |    with self-healing    |  | substituted by:    |
 |                  |   |                         |  | sync-skills.sh     |
 |                  |   | resolved by: the target |  | reading .sync-map  |
 |                  |   | machine itself          |  |                    |
 +------------------+   +-------------------------+  +--------------------+
                                                              |
                         for places a shell never expands ----+
                         (JSON, Python string literals)
```

The two directions:

```
[PUBLISHING]  working copy --> public repo
       |
       |  tracked bytes contain only forms (1)(2)(3) -- never a real name
       v
  privacy-gate.sh        the account names are NOT in the script: putting them
  reads .privacy-names   there would make the script itself the leak. Skips
  (gitignored)           tmp/. Covers known shapes only: passing != safe
       | pass
       v
  git archive HEAD | tar -x -C ../my-config-public
       +-- not cp -r: that copies the local private files gitignore was hiding

[DEPLOYING]  repo --> this machine (Fedora / Ubuntu / a rented GPU box)
       |
  +----+----+
  v         v
(1)(2)     (3)
plain cp   sync-skills.sh deploy, substituting from tools/.sync-map
resolved   verification compares the SUBSTITUTED bytes, so "hashes match"
on target  means "repo == deployed copy, modulo redaction"
```

| Class | Instances | Why it belongs there |
| :--- | :--- | :--- |
| (1) runtime variable | `$HOME`; the `"/mnt/c/Users/$USER"` first probe in `shell_common` | A shell expands it, and it is always right on the Linux side |
| (2) runtime detection | `glob("/mnt/c/Users/*/...")` in `cjk_font.py`, the globs for `WT_SETTINGS` and the `wt.exe` alias, fontconfig generation, `%USERPROFILE%` + `wslpath`, the `~/.cache/wsl-userprofile` fallback | No shell variable can give you the Windows account name |
| (3) placeholder | `<your-home>` in JSON (only two lines left in the whole repo), `<your-windows-user>` covered by `.sync-map` | A shell does not expand anything in those positions |

The design rests on two gitignored runtime files: `tools/.privacy-names` (the real names the
gate scans for) and `tools/.sync-map` (placeholder to real value). Both exist for the same
reason -- **keeping the real values in a runtime file is what lets the scripts themselves be
published**.

Three known weak spots, each with its own row in the [pitfall index](README.md#pitfall-index): the classification can be
chosen wrong and fail silently (`$USER` colliding with drvfs case-insensitivity); the fallback
cache lacked invalidation (now a two-pass self-heal); and the gate only covers known shapes.

