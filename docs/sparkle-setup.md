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

### 4. Run a release

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
   `release/vX.Y.Z` branch and open a pull request.

Sparkle renders `<description>` as HTML in a web view, so the release
notes are generated twice from the same commits: once as markdown for the
GitHub Release body, and once as HTML for the appcast via
`git-cliff --body .github/appcast-body.tera`. Both runs use `cliff.toml`,
so only the body template differs — the grouping rules can't drift apart.

Both read the same `CLIFF_RANGE=(--unreleased --tag "${TAG}")`. This job
runs before the tag exists, so `--latest` would select the *previous*
tagged release — the bug that gave every release through 0.9.0 the prior
version's notes. The step then verifies that every commit git-cliff chose
is really in `$(git describe --tags --abbrev=0)..HEAD` and fails the run
if not, since notes for the wrong release are non-empty and look fine.

Every value interpolated in that template needs `| escape_xml`; Tera does
not escape by default, and an unescaped `<` in a commit subject gets
swallowed by the web view as an unknown tag.

`update_appcast.py` wraps the HTML in CDATA and prepends a small `<style>`
block that tones headings down to body size for the narrow release-notes
pane. The style sets no colors — Sparkle's web view follows the system
appearance, and hardcoding them would break dark mode.

**Phase 2 — you review and merge the PR:**

5. GitHub does not run workflows on bot-opened PRs, so push an empty
   commit (or close+reopen the PR) to trigger the required checks, then
   merge once green.
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
