# Release CI

The release workflow runs when a Git tag is pushed. It builds, signs, notarizes,
zips, and uploads a GitHub Release asset that `mxcl/AppUpdater` can discover.

## Release Asset Names

`AppUpdater` matches assets by normalized semantic version:

- tag `2.0.2` -> `linkq-2.0.2.zip`
- tag `v2.0.2` -> `linkq-2.0.2.zip`

Do not add extra platform words to the filename. Names like
`linkq-macos-2.0.2.zip` will not be picked up.

## Required Repository Variables

Already configured:

```sh
gh variable set APPLE_TEAM_ID --body ZRB8WDV435
gh variable set DEVELOPER_ID_APPLICATION --body "Developer ID Application: Renat Notfullin (ZRB8WDV435)"
```

## Required Repository Secrets

The workflow expects these GitHub Actions secrets:

- `MACOS_CERTIFICATE_P12_BASE64`: base64-encoded `.p12` containing the Developer
  ID Application certificate and private key.
- `MACOS_CERTIFICATE_PASSWORD`: password for that `.p12`.
- `APPLE_ID`: Apple ID used for notarization.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.

Create a Developer ID Application certificate in the Apple Developer portal,
export it from Keychain Access as `.p12`, then upload it:

```sh
base64 -i DeveloperIDApplication.p12 | gh secret set MACOS_CERTIFICATE_P12_BASE64
gh secret set MACOS_CERTIFICATE_PASSWORD
gh secret set APPLE_ID
gh secret set APPLE_APP_SPECIFIC_PASSWORD
```

## Creating A Release

Prefer tags without a `v` prefix:

```sh
git tag 2.0.2
git push origin 2.0.2
```

The workflow will create the GitHub Release if needed and upload
`linkq-2.0.2.zip`.
