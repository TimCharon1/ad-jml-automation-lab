# ad-jml-automation-lab
AD Domain controller Joiners, Movers and Leavers JML lab

# Active Directory Joiner/Mover/Leaver Automation Lab

A single-domain-controller Active Directory lab (`lab.local`) built on an Azure VM, with a PowerShell script that automates the user lifecycle: **joiners**, **movers**, and **leavers**, driven by CSV files.

> This is a learning lab, not a production design. It uses a throwaway domain and fake users.

## What it does

| Mode | What happens | Why it matters |
|---|---|---|
| `Setup` | Creates the `LabCorp` OU tree (IT, HR, Sales, Groups, Disabled) and one security group per department | OUs organize accounts, and groups grant access |
| `Joiner` | Reads `users.csv`, creates each user in their department OU, and adds them to the department group | Consistent onboarding with no hand-clicking |
| `Mover` | Swaps the user's group membership, updates their department, and moves them to the new OU | Prevents permission creep when someone changes roles |
| `Leaver` | Disables the account, removes all group memberships, stamps a description, and moves it to the Disabled OU | Cuts off access quickly while keeping the record for audit |

Every action is written to `jml-log.csv`. Existing OUs, groups and users are skipped, so the script is safe to rerun.

## Environment

- Azure VM running Windows Server 2025 Datacenter: Azure Edition (Gen2), size Standard_D2nds_v6 (2 vCPU, 8 GiB), East US
- Active Directory Domain Services and DNS, new forest `lab.local` (NetBIOS `LAB`), functional level Windows Server 2025
- Domain controller promoted with the Server Manager wizard; the generated command is saved as `promote-dc.ps1`
- RDP restricted to my own IP with a network security group rule

## Repo layout

```
ad-jml-automation-lab/
├── Invoke-JML.ps1
├── promote-dc.ps1.png      (screenshot of the wizard's generated script)
├── users.csv
├── movers.csv
├── leavers.csv
├── jml-log.csv             (sample output)
├── *.png                   (walkthrough screenshots)
└── README.md
```

## How to run

From an elevated PowerShell prompt on the domain controller, in the folder holding the script:

```powershell
.\Invoke-JML.ps1 -Mode Setup
.\Invoke-JML.ps1 -Mode Joiner -CsvPath .\users.csv   # prompts for an initial password
.\Invoke-JML.ps1 -Mode Mover  -CsvPath .\movers.csv
.\Invoke-JML.ps1 -Mode Leaver -CsvPath .\leavers.csv
```

The initial password is typed at a masked prompt. It is never stored in the script or the log.

## Walkthrough

### 1. Domain controller
Installed the AD DS role and promoted the server to a new forest, `lab.local`, using the wizard. The wizard's "View script" output is saved as [`promote-dc.ps1`](promote-dc.ps1.png).

![Domain verified](Domain%20controller%20configured%202.png)

### 2. Setup: OUs and groups
![OU tree](LabCorp%20installed.png)
![Security groups](Confirming%20departments%20installed.png)

### 3. Joiner: six users created
![Joiner output](Initial%20user%20password%20installed.png)

Users landed in their department OUs:

![IT OU](IT%20team%20confirmed.png)
![HR OU](HR%20team%20confirmed.png)
![Sales OU](Sales%20team%20confirmed.png)

### 4. Mover: `fdubois` moves from Sales to IT
Before: in the Sales OU.

![fdubois before](Sales%20team%20confirmed.png)

After: moved to the IT OU, member of `SG-IT`, department updated.

![Mover result](FDubois%20moved%20from%20Sales%20to%20IT.png)
![fdubois after](FDubois%20properties%20confirmed.png)

### 5. Leaver: `bcarter` is offboarded
Account disabled, groups removed, description stamped, and the object moved to the Disabled OU. The record stays for audit purposes.

![Leaver result](BCarter%20Disabled%20confirmed.png)
![bcarter groups](Bcarter%20Member%20propterties.png)
![bcarter disabled](Ben%20Carter%20after%20PS%20confirmation.png)

### 6. Verification
Group membership after the mover and leaver runs:

![Group membership check](Groups%20and%20Users%20after%20confirmation.png)

Final state of all users:

![Summary table](Joiners%20Movers%20Leavers%20Summary.png)

Rerunning Setup prints nothing, and rerunning Joiner skips every existing user, so the script is safe to repeat:

![Rerun skips existing users](Users%20exist%20confirmation.png)

## What broke (and how I fixed it)

- **VM size unavailable.** My first choice, Standard_D2s_v3, returned `NotAvailableForSubscription` in East US. I listed all sizes and picked a current-generation v6 size that was available on my subscription.
- **RDP would not connect.** Azure's access check showed `DenyAllInBound` as the blocking rule, meaning no network security group rule matched my source IP. I added an inbound allow rule for port 3389 limited to my own public IP.
- **RDP broke again the next day.** Error `0x204`. The Network Watcher NSG diagnostic showed that no allow rule matched the source IP, and the Native RDP page had picked up a private adapter address instead of my public IP. I confirmed my real public IP, updated the allow rule's source, and re-ran the check until it passed. Takeaway: home IPs can change, so a source-IP-restricted rule needs rechecking each session.
- **Script file was missing.** `Invoke-JML.ps1` was not found because I was in the wrong folder, and the file I had saved was empty. I recreated the files from PowerShell here-strings, checked sizes with `Get-ChildItem`, and the script ran.

## What I learned

*(Rewrite this in your own words before publishing.)*

- The difference between an OU (organizes and delegates administration) and a security group (grants access).
- Why leavers are disabled and moved instead of deleted: it keeps the audit trail and allows recovery. Deletion happens later, under a retention policy.
- Why movers need both a group change and an OU move, so old permissions don't linger.
- How a script can be made safe to rerun by checking for existing objects first.
- How Azure network security groups evaluate rules by priority, and how to read the NSG diagnostic to find what is blocking traffic.
- This is the on-premises side of identity. Hybrid identity connects a domain like this one to Microsoft Entra ID (Cloud Sync is the next step I plan to try).

## Security notes

- No passwords, subscription IDs, or public IPs are stored in this repo. Screenshots were cropped to remove them.
- The DSRM and VM admin passwords were stored only in a password manager.
- RDP was restricted to a single source IP, and the VM was deallocated when not in use.

## Ideas for improvement

- Generate a unique random password per user instead of one shared initial password.
- Add `-WhatIf` support so changes can be previewed.
- Delete disabled accounts after a retention period.
- Sync the domain to Microsoft Entra ID with Cloud Sync.

