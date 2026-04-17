# ps-runas

Start a PowerShell session in **Windows Terminal** running under the credentials of a specified domain user — entirely from the command line.

---

## Why?

When you need to perform tasks (e.g. Active Directory management) that require a privileged domain account, you normally right-click a shortcut and choose *Run as different user*.  
`ps-runas` does the same thing from a script, making it repeatable and automation-friendly.

---

## Requirements

| Requirement | Notes |
|---|---|
| Windows 10 / Windows Server 2016 or later | Required for `wt.exe` support |
| [Windows Terminal](https://aka.ms/terminal) | Falls back to a plain `powershell.exe` window if not found |
| Windows PowerShell 5.1 **or** PowerShell 7+ | Both are supported |
| Target account must be able to log on interactively | Only required without `-NetOnly`; use `-NetOnly` if the account lacks this right |

---

## Files

```
ps-runas/
├── PsRunAs.psd1                    # Module manifest
├── PsRunAs.psm1                    # Module exports: Start-RunAs and credential cmdlets
├── Start-RunAs.ps1                  # Main script — start a session as a different user
├── Save-Credential.ps1              # Save a credential to disk (DPAPI-encrypted SecureString)
├── Get-SavedCredential.ps1          # Retrieve a previously saved credential
├── Get-SavedCredentialList.ps1      # List saved credentials (simple or detailed output)
├── Remove-SavedCredential.ps1       # Delete a saved credential from disk
└── examples/
    └── Invoke-ADManagement.ps1      # Example: AD management session
```

---

## Usage

Import the module first:

```powershell
Import-Module .\PsRunAs.psd1
```

### Basic — prompt for credentials

```powershell
Start-RunAs -UserName "CONTOSO\AdminUser"
```

You will be prompted for the password.  A new PowerShell console window opens running as `CONTOSO\AdminUser`.

### Pass a pre-built credential

```powershell
$cred = Get-Credential -UserName "CONTOSO\AdminUser" -Message "Enter admin credentials"
Start-RunAs -Credential $cred
```

### Start in a specific directory

```powershell
Start-RunAs -UserName "CONTOSO\AdminUser" -WorkingDirectory "C:\AdminTools"
```

### Use NetOnly when the account lacks interactive logon rights

```powershell
Start-RunAs -UserName "jdoe@contoso.com" -NetOnly
```

The new window runs locally as your own account but all network access (Active Directory,
UNC paths, etc.) uses the specified credentials — identical to `runas /netonly`.

### Set the window title to show the domain and user

```powershell
Start-RunAs -UserName "CONTOSO\AdminUser" -WindowTitle "CONTOSO\AdminUser"
```

The title bar of the new PowerShell window will read `CONTOSO\AdminUser`, making it easy to
identify which account each window is running under when you have multiple sessions open.

### Pre-configure Active Directory cmdlets to target a specific domain

```powershell
Start-RunAs -UserName "CONTOSO\AdminUser" -Domain "contoso.com"
```

Opens a PowerShell console window running as `CONTOSO\AdminUser` with both
`$PSDefaultParameterValues['*-AD*:Server']` and `$PSDefaultParameterValues['*-Dns*:ComputerName']`
pre-set to `contoso.com`.  All AD cmdlets (`Get-ADUser`, `Get-ADGroup`, `Get-ADComputer`, …) and
DNS Server cmdlets (`Get-DnsServerResourceRecord`, `Add-DnsServerResourceRecord`, …) will
automatically target that domain without requiring `-Server` or `-ComputerName` on every call.

Because `-Domain` is specified, `-NetOnly` is automatically enabled — the account does not need
interactive logon rights on the local machine.  Pass `-NetOnly:$false` to require a full
interactive logon instead.

### Record a transcript of the session

```powershell
Start-RunAs -UserName "CONTOSO\AdminUser" -TranscriptPath "C:\Logs\admin-session.log"
```

Opens a PowerShell console window running as `CONTOSO\AdminUser` and automatically starts recording
a full transcript of all input and output to `C:\Logs\admin-session.log`.  The transcript begins at
session start and continues until the window is closed.  If the file already exists the new
transcript is appended to it.

```powershell
# Combine with other options — record a coloured, titled, NetOnly session
Start-RunAs -UserName "CONTOSO\AdminUser" -NetOnly `
    -WindowTitle "CONTOSO\AdminUser" -BackgroundColor DarkBlue -ForegroundColor White `
    -TranscriptPath "C:\Logs\admin-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
```

---

## Parameters

| Parameter | Type | Description |
|---|---|---|
| `-UserName` | `string` | Domain-qualified user name, e.g. `CONTOSO\jdoe` or `jdoe@contoso.com`. Triggers an interactive password prompt. |
| `-Credential` | `PSCredential` | Pre-built credential object. Mutually exclusive with `-UserName`. |
| `-WorkingDirectory` | `string` | Starting directory for the new session. Defaults to the current directory. |
| `-NoNewWindow` | `switch` | Accepted for backwards compatibility; has no effect (Windows Terminal cannot be launched as a different user). |
| `-NetOnly` | `switch` | Uses `LOGON_NETONLY` (equivalent to `runas /netonly`). The new PowerShell window runs under your own local account but uses the supplied credentials for all network access (AD, UNC paths, etc.). Use this when the target account does not have interactive logon rights on this machine. Automatically enabled when `-Domain` is specified; pass `-NetOnly:$false` to override. |
| `-Domain` | `string` | DNS name or domain controller hostname to set as the default server for Active Directory and DNS Server cmdlets in the new session. Sets `$PSDefaultParameterValues['*-AD*:Server']` and `$PSDefaultParameterValues['*-Dns*:ComputerName']` automatically so you can run `Get-ADUser`, `Get-DnsServerResourceRecord`, etc. without specifying `-Server` or `-ComputerName` on every call. Also automatically enables `-NetOnly` (see above). |
| `-WindowTitle` | `string` | Title to display in the title bar of the spawned PowerShell window.  When omitted, the window title is left at the default. Pass the credential's `UserName` to show the domain and user name: `-WindowTitle "CONTOSO\AdminUser"`. |
| `-ArgumentList` | `string[]` | Extra arguments forwarded to the PowerShell executable inside the new session. |
| `-TranscriptPath` | `string` | Absolute path to a file where a full transcript of the spawned session will be recorded. When specified, `Start-Transcript` is called at session start and records all input and output to the given file. If the file already exists the transcript is appended to it. Parent directories must already exist. |

---

## Example: Active Directory management

The `examples/Invoke-ADManagement.ps1` script shows how to use `Start-RunAs.ps1` to open a privileged session and immediately load the **Active Directory** PowerShell module.

### Prerequisites

Install the RSAT Active Directory tools if they are not already present:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

### Run the example

```powershell
.\examples\Invoke-ADManagement.ps1 -DomainAdmin "CONTOSO\ADAdmin"
```

A new Windows Terminal window opens as `CONTOSO\ADAdmin`.  The session automatically:

1. Imports the `ActiveDirectory` module  
2. Confirms the connected domain and PDC emulator  
3. Lists the first 10 enabled user accounts  
4. Lists all members of the **Domain Admins** group  
5. Lists the first 10 domain computers  

The window remains open (`-NoExit`) so you can continue running AD commands interactively.

---

## How it works

`Start-RunAs.ps1` calls [`Start-Process`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process) with the `-Credential` parameter, which uses the Windows `CreateProcessWithLogonW` API under the hood.  This is exactly what *Run as different user* does.

```
Start-Process pwsh.exe -Credential $cred -ArgumentList "-NoExit ..."
```

**Why not Windows Terminal (`wt.exe`)?**  
`wt.exe` is distributed as an MSIX-packaged application.  `CreateProcessWithLogonW` cannot launch packaged apps — attempting to do so always fails with an "incorrect username or password" error, even when the credentials are correct.  The script therefore always launches the PowerShell executable directly in a new console window.

---

## Credential management

The three credential scripts let you save and reuse credentials without being prompted every time.

### Save a credential

```powershell
Save-Credential -Name "CONTOSO-Admin" -UserName "CONTOSO\AdminUser"
```

You are prompted for the password once.  The credential is written to  
`%APPDATA%\ps-cred\CONTOSO-Admin.cred` with the password encrypted by the Windows  
Data Protection API (DPAPI) — only the same Windows user on the same machine can decrypt it.

```powershell
# Save a pre-built credential without a second prompt
$cred = Get-Credential -UserName "CONTOSO\AdminUser" -Message "Enter admin credentials"
Save-Credential -Name "CONTOSO-Admin" -Credential $cred
```

### Retrieve a saved credential

```powershell
$cred = Get-SavedCredential -Name "CONTOSO-Admin"
Start-RunAs -Credential $cred
```

`Get-SavedCredential` decrypts the stored password and returns a `PSCredential` object  
that can be passed directly to `Start-RunAs` or any other cmdlet that accepts `-Credential`.

### Remove a saved credential

```powershell
Remove-SavedCredential -Name "CONTOSO-Admin"

# Preview without deleting
Remove-SavedCredential -Name "CONTOSO-Admin" -WhatIf
```

### List saved credentials

```powershell
Get-SavedCredentialList
```

Returns a simple list of saved credential names.

```powershell
Get-SavedCredentialList -Detailed
```

Returns verbose output per credential with:

- `Name`
- `UserName`
- `User`
- `Domain`
- `SavedAt`
- `Path`

### Credential store parameters

All three scripts share the same `-Name` and `-StorePath` parameters.

| Parameter | Default | Description |
|---|---|---|
| `-Name` | *(required)* | Short label used as the file name (e.g. `"CONTOSO-Admin"` → `CONTOSO-Admin.cred`). |
| `-StorePath` | `%APPDATA%\ps-cred` | Directory where credential files are stored. |
