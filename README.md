# Microsoft Office 365 Update Tool

## User Guide

<a id="toc"></a>
<h2>Table of Contents</h2>

|  |  |
|---|---|
| [1. Overview](#overview) | [10. Activity Log](#activity-log) |
| [2. What Is an Office Update Channel?](#update-channel) | [11. Saving Results](#saving-results) |
| [3. What the Tool Does](#what-the-tool-does) | [12. Silent Operation](#silent-operation) |
| [4. Local Computer Use](#local-computer-use) | [13. Organizational Policies](#organizational-policies) |
| [5. Remote Computer Use](#remote-computer-use) | [14. Common Problems](#common-problems) |
| [6. Required Software and Settings](#required-software-and-settings) | [15. Recommended Use](#recommended-use) |
| [7. Office Application Closing Option](#office-application-closing-option) | [16. Security Guidance](#security-guidance) |
| [8. Timeout Setting](#timeout-setting) | [17. Limitations](#limitations) |
| [9. Understanding the Results](#understanding-the-results) | [18. Quick-Start Summary](#quick-start-summary) |

<h3>Subsections</h3>

|  |  |
|---|---|
| [Local Computer Requirements](#local-computer-requirements) | [Connection Failed](#connection-failed) |
| [Target Computer Requirements](#target-computer-requirements) | [Office Click-to-Run Was Not Found](#office-click-to-run-was-not-found) |
| [Remote Management Requirements](#remote-management-requirements) | [Version Did Not Change](#version-did-not-change) |
| [Network and Security Requirements](#network-and-security-requirements) | [Channel Did Not Change](#channel-did-not-change) |
| [Local Computer](#quick-start-local-computer) | [Release Code Shows N/A](#release-code-shows-na) |
| [Remote Computers](#quick-start-remote-computers) |  |

<a id="overview"></a>
## 1. Overview

The **Microsoft Office 365 Update Tool** is a Windows utility that helps administrators:

- Change the update channel used by **Microsoft 365 Apps**
- Request the newest Office version available on that channel

The tool can work with:

- The computer on which the tool is running
- Single or multiple remote Windows computers
- Up to **15 computers at the same time** to help avoid overwhelming the network
- The currently logged-in Windows account or alternate administrator credentials

This utility updates Microsoft 365 Click-to-Run applications such as:

- Word
- Excel
- Outlook
- PowerPoint
- Access
- Publisher
- OneNote
- Other installed Microsoft 365 desktop applications

> [!IMPORTANT]
> This tool does **not** update Windows, drivers, firmware, browsers, or unrelated applications. It only manages supported **Microsoft 365 Click-to-Run** installations.
>
> This is an independent administration utility and is **not** produced, endorsed, or supported by Microsoft.

---

<a id="update-channel"></a>
## 2. What Is an Office Update Channel?

An **update channel** controls how often Microsoft 365 Apps receive new features, changes, and fixes.

This tool offers the following channel choices:

### Current Channel

Receives new Microsoft 365 features as soon as Microsoft considers them ready for general use. Appropriate for users who want new features quickly.

### Monthly Enterprise Channel

Receives feature updates on a predictable monthly schedule. Often a good choice for organizations that want regular updates with a more controlled release schedule.

### Semi-Annual Enterprise Channel

Receives feature changes less frequently. Commonly used by organizations that prioritize longer testing periods and fewer major changes.

### Semi-Annual Enterprise Channel (Preview)

Provides an early look at the next Semi-Annual Enterprise release. Primarily intended for testing before wider deployment.

### Current Channel (Preview)

Provides an early look at features expected to enter Current Channel. Best used on testing computers rather than critical production systems.

### Beta Channel

Receives very early prerelease features and changes. It may be less stable, and availability can depend on Microsoft licensing and account settings.

> [!WARNING]
> **Beta Channel is not recommended for important production computers.**

---

<a id="what-the-tool-does"></a>
## 3. What the Tool Does

For each selected computer, the tool normally performs these steps:

1. Connects to the computer
2. Confirms that Microsoft 365 Click-to-Run is installed
3. Records the currently installed Office version
4. Requests the selected Microsoft 365 update channel
5. Starts the Microsoft 365 Click-to-Run update process
6. Waits for the installed version to change or for the selected timeout period to expire
7. Records the final version reported by the computer
8. Displays the result in the **Results** tab
9. Allows the combined results to be saved as a **CSV** file

The update request is configured to avoid displaying the normal Office update interface. However, users may still notice:

- Activity or notifications
- Increased network use
- Office applications closing
- Office update prompts

---

<a id="local-computer-use"></a>
## 4. Local Computer Use

To update the computer on which the tool is running:

1. Start the tool as an administrator
2. Select the desired Microsoft 365 update channel
3. Leave the computer-name box blank
4. Choose whether Office applications may be closed automatically
5. Select the maximum amount of time the tool should wait
6. Click **Change Channel and Update**
7. Review the confirmation message
8. Click **Yes** to continue

> [!TIP]
> A blank computer list always means the **local computer**.

You may also enter:

```text
localhost
```

However, leaving the box blank is simpler.

---

<a id="remote-computer-use"></a>
## 5. Remote Computer Use

To update remote computers:

1. Start the tool as an administrator
2. Select the desired update channel
3. Enter the remote computer names

Computer names can be entered **one per line**:

```text
PC-001
PC-002
PC-003
```

They can also be separated by commas:

```text
PC-001, PC-002, PC-003
```

4. If your current Windows account has administrator access to the remote computers, leave alternate credentials disabled
5. If another account must be used, select:

   > **Use alternate credentials for remote computers**

6. Click **Set Credentials** and enter the authorized administrator account
7. Select the maximum wait time
8. Click **Change Channel and Update**
9. Confirm the operation

The tool processes up to **15 computers concurrently**. If more than 15 computers are entered, additional computers wait in a queue until a processing slot becomes available.

For example, if **40 computers** are entered:

- Up to 15 begin first
- New computers begin as earlier tasks finish
- No more than 15 are actively processed at once

Each computer has its own timeout. One slow computer does not prevent other active computers from continuing.

---

<a id="required-software-and-settings"></a>
## 6. Required Software and Settings

<a id="local-computer-requirements"></a>
### Local Computer Requirements

The computer running the tool needs:

- A supported Windows desktop or Windows Server operating system
- Windows PowerShell 5.1
- Microsoft .NET Framework components used by Windows Forms
- Administrator rights
- Network access to the computers being managed
- Permission to run PowerShell scripts
- Access to Microsoft Office update services

> [!NOTE]
> The GUI is designed for **Windows PowerShell 5.1**. It may not behave correctly when launched using **PowerShell 7** unless separately tested and adapted.

<a id="target-computer-requirements"></a>
### Target Computer Requirements

Each local or remote target needs:

- A supported Windows operating system
- Microsoft 365 Apps installed through Click-to-Run
- The Microsoft Office Click-to-Run service
- Sufficient free disk space
- Internet or approved internal update-source access
- Access to the Microsoft Office content delivery network when applicable
- Administrator authorization
- No organizational security product blocking the update process

The tool is **not** designed for older MSI-based Office installations.

<a id="remote-management-requirements"></a>
### Remote Management Requirements

Remote computers additionally need:

- Windows Remote Management (**WinRM**)
- PowerShell remoting enabled
- Windows Firewall rules permitting authorized WinRM traffic
- Working computer-name resolution through DNS or the network
- An account with administrator rights on each target
- Network connectivity between the administrator computer and targets

Common WinRM ports:

- **TCP 5985** for WinRM over HTTP
- **TCP 5986** for WinRM over HTTPS

The exact configuration should be determined by your organization’s security policy. HTTPS or centrally managed domain settings may be preferred.

<a id="network-and-security-requirements"></a>
### Network and Security Requirements

The environment may also require:

- Proxy settings that permit Microsoft 365 update traffic
- VPN connectivity for remote locations
- Firewall permission for Microsoft Office update services
- Endpoint-security approval for PowerShell and `OfficeC2RClient.exe`
- Microsoft 365 licensing appropriate for the selected channel

If an organization uses **Microsoft Configuration Manager**, **Intune**, **Group Policy**, **Cloud Update**, or another update-management platform, those systems may override the selection made by this tool.

---

<a id="office-application-closing-option"></a>
## 7. Office Application Closing Option

The option labeled:

> **Allow Office applications to close automatically**

controls whether the Office updater may close running Office applications.

### When Disabled

The updater attempts to avoid forcing Office applications to close. An update may wait or fail to finish if Word, Excel, Outlook, or another Office application remains open.

### When Enabled

Office applications may close during the update. Users could lose unsaved work.

Before enabling this option:

- Notify affected users
- Ask users to save their work
- Schedule the update during an appropriate maintenance period
- Avoid running it during important meetings or presentations

---

<a id="timeout-setting"></a>
## 8. Timeout Setting

The timeout controls how long the tool waits for each computer to report that its Office version has changed or reached the expected version.

- **Default:** 45 minutes per computer

A timeout does **not** necessarily mean the update failed. It can mean:

- The computer was already current
- Office did not report an expected version
- An Office application was left open
- The download was slow
- The computer lost network connectivity
- A restart or sign-out is needed
- The update continued after the tool stopped waiting
- An organizational policy prevented the channel change

After a timeout, verify the computer manually or run the tool again later.

---

<a id="understanding-the-results"></a>
## 9. Understanding the Results

### Computer Name

The name of the computer that returned the result.

### Requested Channel

The update channel selected by the user.

### Previous Version

The Office version recorded before the update request.

### Expected Version

The target version reported by Microsoft 365 Click-to-Run, when available.

Click-to-Run does not always expose this value. In that case, the field may display **Not reported** or **N/A**.

### Updated Version

The installed Office version found during the final check.

If **Previous Version** and **Updated Version** are identical, the computer might:

- Already be current
- Not have completed the update
- Have a policy or open application preventing the change

<a id="release-code-shows-na"></a>
### Release Code

A four-digit Microsoft 365 release identifier, such as `2608`, when the tool can determine it.

Release-code information can change over time. If the installed build is not recognized, this field may display **N/A**. The complete Office version is the more reliable technical value.

### Version Changed

- **True** means the installed Office version changed while the tool was monitoring it
- **False** means no version change was detected during the monitoring period

### Policy Detected

- **True** means the tool found an Office update policy that may control the channel, update source, or target version

### Status

Common status values include:

#### Updated

The installed version changed and the update appeared to complete.

#### Already Current

The installed version matched the version offered by Click-to-Run.

#### Updated - Verify

The installed version changed, but the final target could not be fully confirmed. Verify Office manually when necessary.

#### Timed Out / No Change

No version change was detected before the selected timeout expired.

#### Connection Failed

The tool could not establish the required remote connection.

#### Failed

The connection was established, but the channel or update operation encountered an error.

#### No Result

The task ended without returning normal result information.

### Message

Provides additional details about the result, policy, connection, or error.

---

<a id="activity-log"></a>
## 10. Activity Log

The **Activity Log** tab shows information such as:

- The selected channel
- Computers placed in the queue
- Completion status
- Previous and final versions
- Connection failures
- Policy warnings
- Processing totals

The log can help identify which computers require manual attention.

> [!NOTE]
> The **Clear Log** button removes the visible log text. It does **not** clear Windows event logs or logs stored on remote computers.

---

<a id="saving-results"></a>
## 11. Saving Results

After processing finishes:

1. Open the **Results** tab
2. Review the result rows
3. Click **Save Results**
4. Select a folder and filename
5. Save the file as **CSV**

CSV files can be opened in Microsoft Excel or imported into reporting systems.

The exported file can include:

- Computer name
- Requested channel
- Previous version
- Expected version
- Updated version
- Release code
- Whether the version changed
- Update-process exit information
- Policy detection
- Final status
- Result message

---

<a id="silent-operation"></a>
## 12. Silent Operation

The tool requests that the Microsoft 365 updater run without displaying its normal update window.

For remote computers, the PowerShell remoting session does not normally display a window on the remote user’s desktop.

Silent operation does **not** guarantee that users will notice nothing. Possible visible effects include:

- Office applications closing
- Office applications temporarily becoming unavailable
- Office notifications
- Increased network or disk activity
- A request to restart an Office application
- Changes appearing the next time Office starts

This tool performs administrative maintenance silently where supported. It is **not** intended to conceal activity from users or administrators.

---

<a id="organizational-policies"></a>
## 13. Organizational Policies

The selected channel can be overridden by:

- Group Policy
- Microsoft Intune
- Microsoft 365 Apps admin center
- Cloud Update
- Microsoft Configuration Manager
- Registry-based Office policies
- Internal Office update locations
- Licensing restrictions

When a policy is detected, the result contains a warning.

> [!IMPORTANT]
> Do **not** remove organizational policies merely to make the tool succeed. Contact the organization’s Microsoft 365 or endpoint-management administrator.

---

<a id="common-problems"></a>
## 14. Common Problems

<a id="connection-failed"></a>
### Connection Failed

Check:

- The computer name is correct
- The computer is turned on
- DNS can resolve the computer name
- WinRM is enabled
- Firewall rules permit WinRM
- The account has remote administrator rights
- The computer is reachable through the LAN or VPN

<a id="office-click-to-run-was-not-found"></a>
### Office Click-to-Run Was Not Found

Possible causes:

- Microsoft 365 Apps is not installed
- An older MSI-based Office edition is installed
- Office is damaged
- The installation uses an unsupported layout

<a id="version-did-not-change"></a>
### Version Did Not Change

Possible causes:

- Office was already current
- Office applications were open
- The update was still downloading
- The timeout was too short
- A policy selected a different channel or version
- The computer could not reach its update source
- Click-to-Run did not report its target version

<a id="channel-did-not-change"></a>
### Channel Did Not Change

Possible causes:

- Group Policy or Intune controls the channel
- Cloud Update controls the device
- The selected channel is unavailable for the installed license
- The Office installation is damaged
- The account did not have administrator rights

<a id="release-code-shows-na"></a>
### Release Code Shows N/A

The complete Office version may be available even when its four-digit release code cannot be determined.

Microsoft introduces new builds regularly. The tool’s release-code information may need to be updated as new builds are published.

---

<a id="recommended-use"></a>
## 15. Recommended Use

Before updating many computers:

1. Test the selected channel on one noncritical computer
2. Confirm that Word, Excel, Outlook, and required add-ins work properly
3. Review organizational update policies
4. Notify users if Office applications may close
5. Confirm that important documents have been saved
6. Begin with a small pilot group
7. Review the exported results
8. Expand deployment only after successful testing

> [!TIP]
> Preview and Beta channels should normally be limited to test devices.

---

<a id="security-guidance"></a>
## 16. Security Guidance

Only authorized administrators should use this tool.

Recommended practices include:

- Use a dedicated administrative account where appropriate
- Do not share or record passwords
- Prefer managed, secured PowerShell remoting
- Use WinRM over HTTPS when required by organizational policy
- Keep Windows and Microsoft 365 security updates current
- Digitally sign the PowerShell script before enterprise distribution
- Verify the script’s source and integrity before running it
- Store exported results securely because they contain computer names and software-version information
- Do not disable security controls solely to make the tool work

---

<a id="limitations"></a>
## 17. Limitations

The tool cannot guarantee that:

- Microsoft will offer a newer build
- A selected channel is permitted by the Office license
- Organizational policy will accept the channel change
- Open Office applications will allow the update to finish
- Every Office build can be translated into a four-digit release code
- A remote computer will remain online throughout the update
- Microsoft will continue supporting every listed channel identifier
- An update will complete before the selected timeout

Microsoft may change channel names, availability, identifiers, update behavior, registry values, and supported versions.

---

<a id="quick-start-summary"></a>
## 18. Quick-Start Summary

<a id="quick-start-local-computer"></a>
### Local Computer

1. Run the tool as Administrator
2. Select a channel
3. Leave the computer list blank
4. Choose the Office-application closing option
5. Click **Change Channel and Update**
6. Confirm and wait for the result

<a id="quick-start-remote-computers"></a>
### Remote Computers

1. Run the tool as Administrator
2. Select a channel
3. Enter remote computer names
4. Select alternate credentials if required
5. Confirm that WinRM is enabled and accessible
6. Click **Change Channel and Update**
7. Review the **Results** and **Activity Log** tabs
8. Save the combined CSV report

---

## End of User Guide
