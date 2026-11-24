# Signing the Windows build

Windows SmartScreen shows "Windows protected your PC / unknown publisher" for unsigned
downloads. The release job in `.github/workflows/ci.yml` signs `AiMMO.exe` with **Azure
Artifact Signing** (formerly Trusted Signing) once the owner has set it up. Until then the
step is skipped and the run logs a warning, so nothing breaks.

## What signing does and doesn't do

- The exe shows a verified publisher (your validated name) instead of "Unknown publisher".
- SmartScreen reputation is earned, not bought. Since 2024 no certificate type (OV, EV or
  Artifact Signing) skips the warning on day one. Reputation builds for the signing identity
  as people download and run signed builds, and every later signed build inherits it.
  Expect the warning to fade over days to weeks of real downloads, not instantly.
- The in-game updater downloads `.pck` packs, not a new exe, so players who installed once
  are not re-prompted by updates. Fresh downloads of the zip are what SmartScreen checks.

## Options considered (Nov 2026)

| Option | Cost | Notes |
| --- | --- | --- |
| Azure Artifact Signing | about $9.99/month (Basic, 5,000 signatures) | Individuals in the US and Canada, organizations in the US, Canada, EU and UK. No hardware token, signs from CI. **Chosen.** |
| OV certificate (Sectigo, DigiCert, Certum…) | about $150–300/year | Key must live on a hardware token or cloud HSM since 2023, which makes CI signing awkward. Same SmartScreen behaviour as Artifact Signing. |
| EV certificate | $400+/year | No longer gives instant SmartScreen trust (removed in 2024). Not worth the premium here. |
| SignPath Foundation | free | Open-source projects only: needs an OSI license and signs under SignPath's name. The repo has no license today. |
| Microsoft Store (MSIX) | free listing | No SmartScreen warning at all, but a different distribution channel and packaging. |

## Setup (owner, one time)

1. In the Azure portal, create an **Artifact Signing account** (Basic tier) in a region near
   you. Note its endpoint, for example `https://eus.codesigning.azure.net/`.
2. In that account, start **Identity validation** (Individual, or Organization if you have
   one). Microsoft checks your ID; allow a few business days.
3. After validation, create a **Certificate profile** of type **Public Trust**. Note its name.
4. Create an app registration in Microsoft Entra ID (for example `aimmo-github-signing`).
   Under *Certificates & secrets → Federated credentials*, add a GitHub Actions credential
   for repository `rp8g7mjrr5-design/AiMMO`, entity type **Branch**, branch `main`.
   No client secret is needed.
5. On the Artifact Signing account, under *Access control (IAM)*, give that app the role
   **Artifact Signing Certificate Profile Signer** (older name: Trusted Signing Certificate
   Profile Signer).
6. In GitHub, *Settings → Secrets and variables → Actions*:
   - Secrets: `AZURE_CLIENT_ID` (the app's client ID), `AZURE_TENANT_ID`,
     `AZURE_SUBSCRIPTION_ID`.
   - Variables: `AZURE_SIGNING_ENDPOINT` (step 1), `AZURE_SIGNING_ACCOUNT` (account name),
     `AZURE_SIGNING_PROFILE` (step 3).

The next push to `main` that changes game code signs the build. To sign right away, run the
CI workflow by hand on `main` (*Actions → CI → Run workflow*). Check it: right-click
`AiMMO.exe` → *Properties → Digital Signatures* should list your name.

## How it works

`azure/login` signs in with GitHub's OIDC token (no stored password), then
[jsign](https://github.com/ebourg/jsign) (pinned by SHA-256) signs and timestamps the exe on
the Linux runner. Godot embeds the game pack in its own PE section, so signing doesn't
disturb it.
