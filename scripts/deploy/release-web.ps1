# PowerShell entry point for approval-based web releases (docs/DEPLOYMENT_AUTOMATION.md).
#   .\scripts\deploy\release-web.ps1 prepare --sha <sha> --label <label> --client-id-from-live
#   .\scripts\deploy\release-web.ps1 approve <release>      # owner, in your own terminal
#   .\scripts\deploy\release-web.ps1 deploy <release>
#   .\scripts\deploy\release-web.ps1 status | health | tls | approvals | history [N]
$ErrorActionPreference = 'Stop'
& python "$PSScriptRoot\release_web.py" @args
exit $LASTEXITCODE
