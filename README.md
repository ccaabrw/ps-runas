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
| Target account must be able to log on interactively | Standard domain account requirement |

---

## Files

```
ps-runas/
├── Start-RunAs.ps1                  # Main script
└── examples/
    └── Invoke-ADManagement.ps1      # Example: AD management session
```

---

## Usage

### Basic — prompt for credentials

```powershell
.\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser"
```

You will be prompted for the password.  A new PowerShell console window opens running as `CONTOSO\AdminUser`.

### Pass a pre-built credential

```powershell
$cred = Get-Credential -UserName "CONTOSO\AdminUser" -Message "Enter admin credentials"
.\Start-RunAs.ps1 -Credential $cred
```

### Start in a specific directory

```powershell
.\Start-RunAs.ps1 -UserName "CONTOSO\AdminUser" -WorkingDirectory "C:\AdminTools"
```

---

## Parameters

| Parameter | Type | Description |
|---|---|---|
| `-UserName` | `string` | Domain-qualified user name, e.g. `CONTOSO\jdoe` or `jdoe@contoso.com`. Triggers an interactive password prompt. |
| `-Credential` | `PSCredential` | Pre-built credential object. Mutually exclusive with `-UserName`. |
| `-WorkingDirectory` | `string` | Starting directory for the new session. Defaults to the current directory. |
| `-NoNewWindow` | `switch` | Accepted for backwards compatibility; has no effect (Windows Terminal cannot be launched as a different user). |
| `-ArgumentList` | `string[]` | Extra arguments forwarded to the PowerShell executable inside the new session. |

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
