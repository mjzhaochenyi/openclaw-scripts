# openclaw-scripts

Deployment and operations scripts for OpenClaw nodes.

## Install OpenClaw Node as a Windows Service

```
curl -sL https://raw.githubusercontent.com/mjzhaochenyi/openclaw-scripts/master/install-node-nssm.bat -o %TEMP%\oc.bat & %TEMP%\oc.bat
```

Run in `cmd`. UAC will prompt for admin rights automatically.

### Prerequisites

- [Node.js](https://nodejs.org/) with `openclaw` installed globally (`npm i -g openclaw`)
- [NSSM](https://nssm.cc/) (`winget install nssm`)
