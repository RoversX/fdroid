# CloseX F-Droid repository

CloseX's [F-Droid](https://f-droid.org) repository, with ThinkTerm for
Android. It is rebuilt each time ThinkTerm publishes a release. Its APKs are
the ones on ThinkTerm's release pages, signed with the same key, so moving
between the two needs no reinstall.

## Add it to F-Droid

The address and its QR code are on the [`dist` branch](../../tree/dist).

## How it works

- `metadata/` holds each app's listing. Its `SourceCode` names the GitHub
  repository whose releases carry the APKs.
- `update.sh` downloads the APKs of the newest three releases, runs
  `fdroid update` to write and sign the index, and leaves the result in
  `site/`.
- `.github/workflows/update.yml` runs it and replaces the `dist` branch with
  `site/`. ThinkTerm's `update-fdroid` workflow starts it once a release is
  published, and the run fails if that release's APK is not in the result.

## Running it by hand

Only a newly published release starts a run. After any other change to the
releases, run **Update repository** from the Actions tab with the tag left
blank, or phones keep being offered what was there before:

- a release was deleted, or its APK replaced;
- a prerelease was turned into a release.

## Secrets

In this repository:

| Secret | Holds |
|---|---|
| `FDROID_KEYSTORE` | the PKCS12 keystore with the key `repo` that signs the index, base64-encoded |
| `FDROID_KEYSTORE_PASSWORD` | its password |

In ThinkTerm's repository, `FDROID_TOKEN`: a fine-grained token with access
to this repository only and Actions set to read and write, which lets
ThinkTerm start the run. When it expires, releases go on but this repository
stops updating, with a warning on ThinkTerm's run; renew it before then.

## The signing key

Made once, with the alias the workflow expects:

```sh
keytool -genkeypair -keystore fdroid-repo.p12 -storetype PKCS12 -alias repo \
  -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=CloseX F-Droid"
base64 -i fdroid-repo.p12 | pbcopy   # then paste it as FDROID_KEYSTORE
```

Keep the keystore and its password backed up outside GitHub: a secret cannot
be read back. Lose the key and every phone has to remove the repository and
add it again under the new fingerprint.

## Trying it locally

```sh
export FDROID_REPO_URL=http://<this machine's address>:8000/fdroid/repo
export FDROID_KEYSTORE_FILE=<keystore> FDROID_KEYSTORE_PASSWORD=<password>
APK_DIR=<directory of APKs> ./update.sh
python3 -m http.server -d site 8000
```
