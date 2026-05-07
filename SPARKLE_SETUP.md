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

### 2. Add GitHub Actions secrets

In the repo's **Settings → Secrets and variables → Actions**, add two
repository secrets:

| Name                  | Value                                      |
|-----------------------|--------------------------------------------|
| `SPARKLE_PUBLIC_KEY`  | The public key string from `generate_keys` |
| `SPARKLE_PRIVATE_KEY` | The contents of `sparkle_priv.key`         |

Storing the public key as a secret (rather than committing it to
`Info.plist`) lets you rotate the key pair without a code change. The
release workflow substitutes `SPARKLE_PUBLIC_KEY_PLACEHOLDER` in the
bundled Info.plist with this value at build time.

### 3. Run a release

```bash
gh workflow run release.yml
```

The workflow will:

1. Substitute the public key into the bundled Info.plist.
2. Build, ad-hoc sign, and DMG-package the app.
3. Sign the DMG with EdDSA using `SPARKLE_PRIVATE_KEY`.
4. Create the GitHub Release with the DMG attached.
5. Prepend a new `<item>` to `site/public/appcast.xml`.
6. Push the appcast to `main`, which triggers `deploy-site.yml` and
   publishes the appcast at <https://alecf.github.io/totalrecall/appcast.xml>.

Subsequent launches of installed copies will check that URL daily and
prompt the user to install the new version.

## Key rotation

If the private key is ever exposed:

1. Run `generate_keys` again to create a new pair.
2. Update both `SPARKLE_PUBLIC_KEY` and `SPARKLE_PRIVATE_KEY` secrets.
3. Cut a new release. Existing installs will need to be manually
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
