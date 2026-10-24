#!/usr/bin/env bash
# Installed outside the web root and invoked by a forced SSH command.
set -Eeuo pipefail
umask 077
base=/home/u931810717/domains/api.rentalmoney.in
deploy="$base/deployment"
php=/opt/alt/php84/usr/bin/php
if [[ ! ${SSH_ORIGINAL_COMMAND:-} =~ ^deploy-backend\ ([a-f0-9]{40})$ ]]; then
  echo 'Only deploy-backend <commit SHA> is permitted.' >&2
  exit 64
fi
sha="${BASH_REMATCH[1]}"
mkdir -p "$deploy/releases"
exec 9>"$deploy/deploy.lock"
flock -w 600 9
release="$deploy/releases/$sha"
archive=$(mktemp "$deploy/source.XXXXXX.tar.gz")
switched=false
previous=$(readlink -f "$base/repository/laravel-backend")
cleanup() {
  status=$?
  rm -f -- "$archive"
  if (( status != 0 )) && $switched; then
    ln -s "$previous" "$deploy/rollback-link"
    mv -Tf "$deploy/rollback-link" "$base/repository/laravel-backend"
    echo 'Deployment failed; previous code restored. Review migrations before retrying.' >&2
  fi
  exit "$status"
}
trap cleanup EXIT
cat > "$archive"
# Never extract links, traversal paths or special files from an uploaded archive.
python3 - "$archive" <<'PY'
import sys, tarfile
from pathlib import PurePosixPath
with tarfile.open(sys.argv[1], 'r:gz') as archive:
    members = archive.getmembers()
    if not members or sum(m.size for m in members) > 250_000_000:
        raise SystemExit('Invalid source archive size')
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or '..' in path.parts or not (member.isfile() or member.isdir()):
            raise SystemExit('Unsafe source archive entry')
        if path.parts[0] in {'.env', 'vendor', 'node_modules'}:
            raise SystemExit('Source archive contains private or generated files')
PY
if [[ -d "$release" ]]; then
  if [[ "$previous" == "$release" ]]; then
    echo "Already deployed $sha"
    exit 0
  fi
  echo 'Release already exists; use a new commit for a retry.' >&2
  exit 65
fi
mkdir "$release"
tar -xzf "$archive" -C "$release" --no-same-owner --no-same-permissions
test -f "$release/artisan"
test -f "$release/composer.lock"
cd "$release"
ln -s "$deploy/shared/.env" .env
# Remove only the tracked empty scaffold in this new release.
rm -rf -- "$release/storage"
ln -s "$deploy/shared/storage" storage
mkdir -p bootstrap/cache
"$php" /usr/local/bin/composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader
"$php" artisan migrate --force --no-interaction
"$php" artisan config:cache
"$php" artisan route:cache
"$php" artisan view:cache
chmod 600 bootstrap/cache/config.php
rsync -a --chmod=D755,F644 --exclude=index.php --exclude=.htaccess --exclude=storage public/ "$base/public_html/"
ln -s "$release" "$deploy/next-link"
mv -Tf "$deploy/next-link" "$base/repository/laravel-backend"
switched=true
# PHP keeps the compiled routes and config in memory. Without a reset the site can
# keep serving the previous release's routes after the switch (a new endpoint
# answering "not found" while the code is in place). The reset has to run inside
# the web server's own PHP, hence a one-off file fetched over HTTPS and removed
# straight away. Best effort: it must never fail an otherwise good deploy.
reset_php_cache() {
  local file="oc-reset-${sha:0:12}-$RANDOM$RANDOM.php"
  printf '<?php echo function_exists("opcache_reset") && opcache_reset() ? "opcache reset" : "opcache not reset";\n' > "$base/public_html/$file"
  chmod 644 "$base/public_html/$file"
  local status=0
  curl --silent --show-error --connect-timeout 10 --max-time 30 "https://api.rentalmoney.in/$file" || status=$?
  rm -f -- "$base/public_html/$file"
  return "$status"
}
# Called after ||, so a failure inside never trips `set -e` (and the rollback).
reset_php_cache || echo 'Could not reset the PHP cache automatically.' >&2
echo
healthy=false
for attempt in 1 2 3 4 5; do
  if curl --fail --silent --show-error --connect-timeout 10 --max-time 30 \
    'https://api.rentalmoney.in/api/v1/products?limit=1' | \
    python3 -c 'import json,sys; r=json.load(sys.stdin); assert r.get("status")=="success" and isinstance(r.get("data"),list)'; then
    healthy=true
    break
  fi
  sleep 2
done
$healthy || exit 1
printf '%s\n' "$sha" > "$deploy/current-sha"
switched=false
echo "Backend deployed successfully: $sha"
