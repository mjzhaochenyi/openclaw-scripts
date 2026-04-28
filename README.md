# openclaw-scripts

Deployment and operations scripts for OpenClaw nodes.

## Install OpenClaw Node as a Windows Service

```
curl -sL https://raw.githubusercontent.com/mjzhaochenyi/openclaw-scripts/master/install-node-nssm.bat -o %TEMP%\oc.bat & %TEMP%\oc.bat
```

Run in `cmd`. UAC will prompt for admin rights automatically. Runs as **Local System** (no password needed).

### User Account Mode (recommended if you need desktop/browser access)

```
curl -sL https://raw.githubusercontent.com/mjzhaochenyi/openclaw-scripts/master/install-node-nssm-user.bat -o %TEMP%\oc.bat & %TEMP%\oc.bat
```

Runs the service under your Windows user account (prompts for username and password). Use this if the node needs access to the user session (e.g. opening browsers, GUI apps).

### Prerequisites

- [Node.js](https://nodejs.org/) with `openclaw` installed globally (`npm i -g openclaw`)
- [NSSM](https://nssm.cc/) (`winget install nssm`)
