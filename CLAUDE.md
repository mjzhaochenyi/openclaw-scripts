# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Collection of deployment/operations scripts for the [OpenClaw](https://github.com/mjzhaochenyi/openclaw-scripts) distributed node system. Currently contains a single PowerShell installer script.

## Repository Contents

- **`install-node-nssm.bat`** — Batch script that installs an OpenClaw Node as a Windows Service via [NSSM](https://nssm.cc/) running as **Local System**. Auto-elevates via UAC, auto-discovers `nssm.exe`, `node.exe`, and the globally-installed `openclaw` npm package, then configures NSSM with auto-restart, stdout/stderr logging to `~/.openclaw/`, and grants SYSTEM ACL on the state directory.
- **`install-node-nssm-user.bat`** — Same as above but runs the service under a **user account** (prompts for username/password). Grants "Log on as a service" right and ACL. Use this when the node needs access to the user's desktop session (e.g. browser, GUI).

## Conventions

- Scripts target **Windows / PowerShell 5.1+**.
- All scripts should use PowerShell-native constructs (no bash-isms like ternary `? :` or inline `if` — these were removed in commit history).
- Default TLS port is **443**, default plain port is **18789**.
- OpenClaw node entry point is expected at `<npm global>/openclaw/dist/index.js`.
- Service logs go to `$env:USERPROFILE\.openclaw\` (`node.log` / `node-error.log`).
