#!/bin/bash
# Builds the repository into site/: the APKs of the newest releases of each
# app in metadata/, an index signed with this repository's key, and a README
# with the link that adds it to F-Droid. The workflow publishes site/ as the
# dist branch; anything that serves files can serve it as it is.
#
# Needs fdroid (fdroidserver) and its Python on PATH, an Android SDK at
# ANDROID_HOME, a JDK, gh signed in, and for config.yml:
#   FDROID_REPO_URL           where site/fdroid/repo is served
#   FDROID_KEYSTORE_FILE      the PKCS12 keystore holding the key "repo"
#   FDROID_KEYSTORE_PASSWORD  its password
# APK_DIR=<dir> takes the APKs from a directory instead of the releases.
# CACHE=<file> is a previous run's site/cache/apkcache.json, which keeps the
# date each version was first offered.
# EXPECT_TAG=<tag> is the release that asked for this run: the run fails
# unless that release's APKs are among those it publishes.
set -euo pipefail
: "${FDROID_REPO_URL:?}" "${FDROID_KEYSTORE_FILE:?}" "${FDROID_KEYSTORE_PASSWORD:?}"
# Paths may be given relative to where the script was started; they are
# made absolute before it changes directory.
[ -z "${APK_DIR:-}" ] || APK_DIR=$(cd "$APK_DIR" && pwd)
if [ -n "${CACHE:-}" ] && [ -f "$CACHE" ]; then
  CACHE=$(cd "$(dirname "$CACHE")" && pwd)/$(basename "$CACHE")
else
  CACHE=
fi
FDROID_KEYSTORE_FILE=$(cd "$(dirname "$FDROID_KEYSTORE_FILE")" && pwd)/$(basename "$FDROID_KEYSTORE_FILE")
cd "$(dirname "$0")"

# How many releases of each app a phone can choose from.
keep=${KEEP:-3}

# fdroid works in build/, on copies, so the checkout keeps only its sources.
rm -rf build site
mkdir -p build/repo build/tmp
cp -R metadata icon.png build/
cp config.yml build/config.yml
printf 'repo_url: "%s"\n' "$FDROID_REPO_URL" >> build/config.yml
# fdroid wants its config private, as one holding passwords would be.
chmod 600 build/config.yml
cd build

if [ -n "${APK_DIR:-}" ]; then
  cp "$APK_DIR"/*.apk repo/
else
  published=" "
  for meta in metadata/*.yml; do
    source=$(sed -n 's#^SourceCode: *https://github\.com/\([^/]*/[^/[:space:]]*\).*#\1#p' "$meta")
    [ -n "$source" ] || { echo "$meta names no GitHub SourceCode" >&2; exit 1; }
    got=0
    # Newest first. A release without an APK, from before the app shipped,
    # is passed over. Every query is its own assignment, so one that fails
    # stops the run rather than read as "no APK here": that would publish an
    # index quietly lacking the newest release.
    tags=$(gh release list --repo "$source" --exclude-drafts --exclude-pre-releases \
      --limit 50 --json tagName --jq '.[].tagName')
    for tag in $tags; do
      [ "$got" -lt "$keep" ] || break
      assets=$(gh release view "$tag" --repo "$source" --json assets --jq '.assets[].name')
      if printf '%s\n' "$assets" | grep -q '\.apk$'; then
        gh release download "$tag" --repo "$source" --pattern '*.apk' --dir repo
        got=$((got + 1))
        published="$published$tag "
      fi
    done
    echo "$source: $got release(s)"
  done
  # The release that asked for this run may not be listed yet, a moment
  # after it was published; better to fail and be run again than to look
  # done without it.
  if [ -n "${EXPECT_TAG:-}" ]; then
    case "$published" in
      *" $EXPECT_TAG "*) ;;
      *) echo "release $EXPECT_TAG is not among those found:$published" >&2; exit 1 ;;
    esac
  fi
fi
ls repo/*.apk >/dev/null 2>&1 || { echo "no APKs to publish" >&2; exit 1; }

if [ -n "${CACHE:-}" ] && [ -f "$CACHE" ]; then
  cp "$CACHE" tmp/apkcache.json
fi
fdroid update

# The link F-Droid adds the repository from: its address, and the
# fingerprint of the key that signs the index, which the phone holds every
# later update to.
fingerprint=$(keytool -list -v -keystore "$FDROID_KEYSTORE_FILE" \
  -storepass:env FDROID_KEYSTORE_PASSWORD -alias repo \
  | sed -n 's/^.*SHA256: *//p' | tr -d ':' | head -1)
[ -n "$fingerprint" ] || { echo "no fingerprint for the key \"repo\"" >&2; exit 1; }
link="$FDROID_REPO_URL?fingerprint=$fingerprint"

cd ..
mkdir -p site/fdroid site/cache
# status/ is fdroid's run report, with the build machine's tool paths in it;
# no client reads it.
rm -rf build/repo/status
mv build/repo site/fdroid/repo
cp build/tmp/apkcache.json site/cache/
printf '%s\n' "$link" > site/link.txt
python3 -c 'import sys, qrcode; qrcode.make(sys.argv[1]).save(sys.argv[2])' "$link" site/qr.png
cat > site/README.md <<EOF
# CloseX F-Droid repository

ThinkTerm for Android, from the newest ThinkTerm releases.

## Add it to F-Droid

In F-Droid, open Settings, then Repositories, tap +, and scan this code or
paste the address below it:

![The repository's address as a QR code](qr.png)

\`\`\`
$link
\`\`\`

F-Droid uses that fingerprint to check that the index really comes from this
repository.

This branch is rebuilt from the releases each time ThinkTerm publishes one.
EOF
echo "$link"
