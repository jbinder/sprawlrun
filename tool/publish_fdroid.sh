#!/usr/bin/env bash
#
# Prepares an F-Droid submission end to end, as far as it can be automated.
#
# What it does NOT do, because it cannot: fork fdroiddata and open the merge
# request. Both need a GitLab account and either `glab` or the web UI. The
# script stops at that point and prints exactly what is left.
#
#   tool/publish_fdroid.sh [--fdroiddata DIR] [--skip-build] [--yes]
#
#   --fdroiddata DIR  checkout of your fdroiddata fork (default: ~/fdroiddata)
#   --skip-build      trust an existing verified build; skips ~5 minutes
#   --yes             do not prompt before tagging and pushing
#
# Tagging and pushing are the only irreversible steps and are confirmed
# separately. Everything before them is read-only or local.

set -euo pipefail

PKG=io.github.jbinder.sprawlrun
FDROIDDATA="${HOME}/fdroiddata"
SKIP_BUILD=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fdroiddata) FDROIDDATA="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --yes)        ASSUME_YES=1; shift ;;
    -h|--help)    sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$(dirname "$0")/.."
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight --
step 'Preflight'

[[ -f pubspec.yaml ]] || die 'not in the project root'

VERSION_LINE=$(grep -m1 '^version:' pubspec.yaml | tr -d ' ')
VERSION_NAME=${VERSION_LINE#version:}; VERSION_NAME=${VERSION_NAME%%+*}
VERSION_CODE=${VERSION_LINE##*+}
TAG="v${VERSION_NAME}"
[[ -n $VERSION_NAME && -n $VERSION_CODE ]] || die "cannot parse version from: $VERSION_LINE"
ok "version ${VERSION_NAME}, versionCode ${VERSION_CODE}, tag ${TAG}"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ $BRANCH == main ]] || die "on branch '${BRANCH}', expected main"
ok "on main"

[[ -z $(git status --porcelain) ]] \
  || die 'working tree is dirty — commit or stash first, the tag must point at a clean tree'
ok 'working tree clean'

if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  die "tag ${TAG} already exists — bump the version in pubspec.yaml first"
fi
ok "tag ${TAG} is free"

# The buildserver reads pubspec.lock; an untracked one makes the build
# unreproducible and --enforce-lockfile fail.
git ls-files --error-unmatch pubspec.lock >/dev/null 2>&1 \
  || die 'pubspec.lock is not tracked — F-Droid needs it committed'
ok 'pubspec.lock is tracked'

AVAIL_KB=$(df -Pk . | awk 'NR==2 {print $4}')
if (( SKIP_BUILD == 0 )) && (( AVAIL_KB < 6000000 )); then
  die "only $((AVAIL_KB/1024/1024))G free; a cold release build needs ~6G. Free space or pass --skip-build"
fi
ok "$((AVAIL_KB/1024/1024))G free on the build filesystem"

# ------------------------------------------------------------------- checks --
step 'Analyzer and tests'
fvm flutter analyze >/dev/null || die 'analyzer is not clean'
ok 'analyzer clean'
fvm flutter test >/dev/null || die 'tests are failing'
ok 'tests pass'

# ------------------------------------------------------- unsigned build gate --
APK=build/app/outputs/flutter-apk/app-release.apk
BUILD_TOOLS=$(find /opt/android-sdk/build-tools -maxdepth 1 -mindepth 1 -type d \
              | sort -V | tail -1)
[[ -n $BUILD_TOOLS ]] || die 'no Android build-tools found under /opt/android-sdk'

if (( SKIP_BUILD )); then
  step 'Unsigned build (skipped)'
  [[ -f $APK ]] || die "--skip-build given but ${APK} does not exist"
  ok 'reusing existing APK'
else
  step 'Building unsigned, exactly as F-Droid will'
  # key.properties absent is what makes the release build unsigned. Restore it
  # however this exits — an interrupted run must not leave signing broken.
  restore_key() {
    if [[ -f android/key.properties.publish-aside ]]; then
      mv -f android/key.properties.publish-aside android/key.properties
      printf '    restored android/key.properties\n'
    fi
  }
  trap restore_key EXIT INT TERM
  if [[ -f android/key.properties ]]; then
    mv android/key.properties android/key.properties.publish-aside
  fi
  fvm flutter build apk --release || die 'release build failed'
  restore_key
  trap - EXIT INT TERM
  ok 'built'
fi

step 'Verifying the artifact'
[[ -f $APK ]] || die "no APK at ${APK}"

# F-Droid signs the APK itself and rejects one that arrives pre-signed.
if "${BUILD_TOOLS}/apksigner" verify "$APK" >/dev/null 2>&1; then
  die 'APK IS SIGNED — F-Droid requires an unsigned artifact. Was key.properties present?'
fi
if unzip -l "$APK" | grep -qiE 'META-INF/.*\.(RSA|DSA|EC|SF)'; then
  die 'APK contains signature blocks'
fi
ok 'unsigned'

APK_VC=$("${BUILD_TOOLS}/aapt2" dump badging "$APK" 2>/dev/null \
         | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p" | head -1)
[[ $APK_VC == "$VERSION_CODE" ]] \
  || die "APK versionCode ${APK_VC} does not match pubspec ${VERSION_CODE}"
ok "versionCode ${APK_VC} matches pubspec"

if "${BUILD_TOOLS}/aapt2" dump permissions "$APK" | grep -q 'android.permission.INTERNET'; then
  die 'INTERNET permission present — the offline claim would be false'
fi
ok 'no INTERNET permission'

# Excluding the GMS group is what keeps the app free of Play Services. A new
# plugin can silently reintroduce it, so this is re-checked every release.
DEXDIR=$(mktemp -d); trap 'rm -rf "$DEXDIR"' EXIT
unzip -q -o "$APK" 'classes*.dex' -d "$DEXDIR"
GOOGLE=0; DEFINED=0
for dex in "$DEXDIR"/classes*.dex; do
  mapfile -t names < <("${BUILD_TOOLS}/dexdump" -f "$dex" 2>/dev/null \
    | sed -n "s/.*Class descriptor  *: *'L\([^;]*\);'.*/\1/p")
  DEFINED=$(( DEFINED + ${#names[@]} ))
  GOOGLE=$(( GOOGLE + $(printf '%s\n' "${names[@]}" | grep -c '^com/google' || true) ))
done
(( GOOGLE == 0 )) || die "${GOOGLE} classes under com/google are defined in the dex"
ok "${DEFINED} classes defined, zero under com/google"

SHA=$(sha256sum "$APK" | cut -d' ' -f1)
ok "sha256 ${SHA}"

# ------------------------------------------------------------- tag and push --
step 'Tag and push'
if (( ASSUME_YES == 0 )); then
  cat <<PROMPT

  About to run, against origin ($(git remote get-url origin)):
      git tag -a ${TAG} -m "SPRAWL//RUN ${VERSION_NAME}"
      git push origin main
      git push origin ${TAG}

  F-Droid resolves the build from ${TAG}, so it must exist on the remote.
  This is the point of no return: a pushed tag is public.

PROMPT
  # `|| true` so a non-interactive run (no stdin) falls through to the refusal
  # below instead of dying without explanation.
  reply=''
  read -r -p "  Type ${TAG} to proceed, anything else to stop here: " reply || true
  [[ $reply == "$TAG" ]] || die 'stopped before tagging; everything above is still valid'
fi

git tag -a "$TAG" -m "SPRAWL//RUN ${VERSION_NAME}"
git push origin main
git push origin "$TAG"
ok "pushed main and ${TAG}"

# ---------------------------------------------------------------- metadata ---
step 'Metadata'
if [[ ! -d $FDROIDDATA/metadata ]]; then
  cat <<MISSING
    No fdroiddata checkout at ${FDROIDDATA}.
    Fork it once at https://gitlab.com/fdroid/fdroiddata/-/forks/new then:
        git clone git@gitlab.com:jbinder/fdroiddata.git ${FDROIDDATA}
    Re-run with --skip-build --yes to carry on from here; the tag is already
    pushed, so nothing above needs repeating.
MISSING
  exit 1
fi

TARGET="${FDROIDDATA}/metadata/${PKG}.yml"
# The annotated draft is the single source of truth; fdroiddata wants it clean.
# Only whole-line comments are stripped, so no value can be damaged.
grep -v '^[[:space:]]*#' docs/fdroid-metadata.yml | cat -s | sed '/./,$!d' > "$TARGET"
python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" "$TARGET" \
  || die 'generated metadata is not valid YAML'
grep -q "commit: ${TAG}" "$TARGET" \
  || die "metadata does not reference ${TAG} — update docs/fdroid-metadata.yml"
ok "wrote ${TARGET}"

# Stripping comments is not enough: fdroiddata enforces canonical formatting
# (fixed field order, ndk last, no blank lines inside a build entry) and fails
# the pipeline on formatting alone. rewritemeta is the authority, so run it and
# then confirm a second pass is a no-op — that is exactly the CI gate.
if command -v fdroid >/dev/null; then
  ( cd "$FDROIDDATA" && fdroid rewritemeta "$PKG" >/dev/null ) \
    || die 'fdroid rewritemeta failed'
  cp "$TARGET" "${TARGET}.canon"
  ( cd "$FDROIDDATA" && fdroid rewritemeta "$PKG" >/dev/null ) || true
  if ! diff -q "${TARGET}.canon" "$TARGET" >/dev/null; then
    rm -f "${TARGET}.canon"
    die 'rewritemeta is not idempotent — CI would reject the formatting'
  fi
  rm -f "${TARGET}.canon"
  ok 'canonical formatting (rewritemeta is a no-op)'
  ( cd "$FDROIDDATA" && fdroid lint "$PKG" ) && ok 'fdroid lint clean'
else
  cat <<'NOFDROID'
    fdroid not installed, so formatting was NOT canonicalised and CI will
    likely fail on it. Install it into a venv and re-run:
        python3 -m venv ~/.local/venvs/fdroidserver
        ~/.local/venvs/fdroidserver/bin/pip install fdroidserver
        PATH="$HOME/.local/venvs/fdroidserver/bin:$PATH" tool/publish_fdroid.sh ...
NOFDROID
fi

# ------------------------------------------------------------- what is left --
step "Done — remaining steps are manual"
cat <<NEXT
    1. Commit and push the metadata in your fdroiddata fork:
           cd ${FDROIDDATA}
           git checkout -b ${PKG}
           git add metadata/${PKG}.yml
           git commit -m "New app: SPRAWL//RUN"
           git push -u origin ${PKG}

       The push prints a ready-made merge-request link. If you miss it:
           https://gitlab.com/jbinder/fdroiddata/-/merge_requests/new?merge_request%5Bsource_branch%5D=${PKG}

    2. Target fdroid/fdroiddata:master and paste the reviewer notes from the
       bottom of docs/fdroid-metadata.yml into the description. Mention the
       56 MB universal APK there yourself — better raised than discovered.

    Artifact verified this run:
       ${APK}
       ${VERSION_NAME} (${VERSION_CODE}), unsigned, sha256 ${SHA}
NEXT
