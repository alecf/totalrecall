# Sparkle auto-update setup

The repository ships everything needed for in-app auto-updates *except*
the EdDSA key pair, which has to be generated once by a human and stored
in GitHub Actions secrets. Until that one-time setup is done, the
release workflow will refuse to run.

## One-time setup

### 1. Generate an EdDSA key pair

Sparkle's `generate_keys` tool puts the private key in your macOS
Keychain and prints the public key to stdout.

```bash
brew install --cask sparkle
generate_keys
# → Public key: AbCd... (base64)
```

The private key is now in your login Keychain under the item
"https://sparkle-project.org". Export it for use in CI:

```bash
generate_keys -x sparkle_priv.key
cat sparkle_priv.key   # base64 string, ~64 chars
```

Treat `sparkle_priv.key` like an SSH key: never commit it, delete the
file once you've copied the contents into the secret.

### 2. Commit the public key

Public keys are not sensitive — paste the value `generate_keys` printed
into `Distribution/Info.plist` as the `SUPublicEDKey` string and commit
it. The released app trusts only this exact key, so this is what
prevents a tampered DMG from being accepted.

```xml
<key>SUPublicEDKey</key>
<string>YOUR_BASE64_PUBLIC_KEY_HERE</string>
```

### 3. Add the private key as a GitHub Actions secret

In the repo's **Settings → Secrets and variables → Actions**, add one
repository secret:

| Name                  | Value                              |
|-----------------------|------------------------------------|
| `SPARKLE_PRIVATE_KEY` | The contents of `sparkle_priv.key` |

Or via the CLI:

```bash
gh secret set SPARKLE_PRIVATE_KEY < sparkle_priv.key
rm sparkle_priv.key   # canonical copy lives in your Keychain
```

### 4. Create the release GitHub App

`release.yml` opens the appcast pull request as a GitHub App rather than
as `github-actions[bot]`. This is not cosmetic. GitHub refuses to start a
workflow run for any event created with the default `GITHUB_TOKEN` — it
is how the platform stops workflows triggering themselves in a loop — so
a PR opened with that token arrives with no CI at all, and its required
checks stay unfilled until a human pushes an empty commit or closes and
reopens it. An installation token is a separate identity, so `ci.yml`,
`pr-title.yml` and `pr-screenshot.yml` all start the moment the PR opens,
and auto-merge has real checks to wait on.

Create the app at **Settings → Developer settings → GitHub Apps → New
GitHub App** (a personal app is fine — it never needs to be public):

- **Homepage URL**: the repository URL is fine.
- Uncheck **Webhook → Active**; the app receives nothing.
- **Repository permissions**: `Contents: Read and write` (push the
  `release/*` branch) and `Pull requests: Read and write` (open the PR and
  enable auto-merge). Nothing else.
- **Where can this be installed**: only this account.

Create it, then **Generate a private key** (downloads a `.pem`) and
**Install App** onto `totalrecall`. Store both halves as secrets:

| Name                       | Value                                   |
|----------------------------|-----------------------------------------|
| `RELEASE_APP_ID`           | The app's numeric App ID                |
| `RELEASE_APP_PRIVATE_KEY`  | The full contents of the `.pem` file    |

```bash
gh secret set RELEASE_APP_ID --body "1234567"
gh secret set RELEASE_APP_PRIVATE_KEY < ~/Downloads/totalrecall-release.private-key.pem
rm ~/Downloads/totalrecall-release.private-key.pem
```

Unlike a personal access token, an app private key does not expire, and
the installation tokens minted from it last an hour and are scoped to
this one repository.

Two repository settings make the rest of the flow hands-off:

- **Settings → General → Allow auto-merge** must be on, or `release.yml`
  falls back to leaving the PR for a manual merge (with a warning in the
  job log).
- `main` must require at least one status check. Auto-merge can only be
  requested on a PR that is *not* already mergeable; with no required
  checks there is nothing to wait for and the request is rejected.

If `main` also requires an approving review, the release PR waits for
yours before auto-merge fires. Since the app opens the PR rather than
you, you are free to approve it yourself.

### 5. Run a release

```bash
gh workflow run release.yml
```

Releasing is two-phase and gated on a merged pull request — the workflow
never commits to `main` or publishes anything to users on its own.

**Phase 1 — `release.yml` (the dispatch above) will:**

1. Build, ad-hoc sign, and DMG-package the app (the committed Info.plist
   already carries the public key).
2. Sign the DMG with EdDSA using `SPARKLE_PRIVATE_KEY`.
3. Create a **draft** GitHub Release with the DMG attached (no tag yet,
   nothing public).
4. Prepend a new `<item>` to `site/public/appcast.xml` on a
   `release/vX.Y.Z` branch, open a pull request as the release app, and
   turn on auto-merge.

Sparkle renders `<description>` as HTML in a web view, so the release
notes are generated twice from the same commits: once as markdown for the
GitHub Release body, and once as HTML for the appcast via
`git-cliff --body .github/appcast-body.tera`. Both runs use `cliff.toml`,
so only the body template differs — the grouping rules can't drift apart.

Every value interpolated in that template needs `| escape_xml`; Tera does
not escape by default, and an unescaped `<` in a commit subject gets
swallowed by the web view as an unknown tag.

`update_appcast.py` wraps the HTML in CDATA and prepends a small `<style>`
block that tones headings down to body size for the narrow release-notes
pane. The style sets no colors — Sparkle's web view follows the system
appearance, and hardcoding them would break dark mode.

**Phase 2 — the PR merges itself:**

5. CI starts on the PR as soon as it opens, and auto-merge squashes it in
   once the required checks pass. Nothing to do unless you want to stop
   it: disable auto-merge on the PR, or close it, and the draft Release
   stays unpublished.
6. The merge runs `release-publish.yml`, which flips the draft Release to
   published (creating the tag at the merge commit). `deploy-site.yml`
   picks up the appcast change on `main` and publishes it at
   <https://alecf.github.io/totalrecall/appcast.xml>.

Subsequent launches of installed copies will check that URL daily and
prompt the user to install the new version.

## Key rotation

If the private key is ever exposed:

1. Run `generate_keys` again to create a new pair.
2. Replace `SUPublicEDKey` in `Distribution/Info.plist` with the new
   public key and commit.
3. Update the `SPARKLE_PRIVATE_KEY` secret with the new private key.
4. Cut a new release. Existing installs will need to be manually
   re-downloaded once, since their bundled public key no longer
   matches; future updates resume working automatically.

## How verification works

The shipped `Info.plist` embeds the public key. When Sparkle downloads
an update, it computes the EdDSA signature of the DMG and checks it
against the embedded public key. A mismatch — including a man-in-the-
middle attempt to swap a malicious DMG into the GitHub CDN — causes the
update to be rejected. This is independent of Apple's code signing,
which the project intentionally skips.

## Local verification (optional)

To verify a freshly-built DMG matches the appcast signature without
running the full update flow:

```bash
./sparkle-tools/bin/sign_update -s "$SPARKLE_PRIVATE_KEY" path/to/DMG
# Compare the printed sparkle:edSignature="..." with the value in
# site/public/appcast.xml for the same release.
```
