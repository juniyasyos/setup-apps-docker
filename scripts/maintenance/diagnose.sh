#!/bin/bash

docker-compose -f docker-compose-multi-apps.yml exec app-siimut sh -c '
  echo "UID/GID in container:"; id || true
  echo; echo "Storage dirs:"; ls -ld storage storage/framework storage/framework/views bootstrap/cache || true
  echo; echo "List storage/framework/views (first 50):"; ls -la storage/framework/views 2>/dev/null | head -50 || true
'

docker-compose -f docker-compose-multi-apps.yml exec app-siimut sh -c '
  f="storage/framework/views/28a88a3358c99b142599cc14f5360aca.php"
  if [ -e "$f" ]; then ls -l "$f" || true; stat "$f" 2>/dev/null || echo "stat unavailable"; fi
'

# set owner to UID 1000 (www) inside volume
docker run --rm -v siimut_storage:/data alpine sh -c 'chown -R 1000:1000 /data || true'
docker run --rm -v siimut_bootstrap_cache:/data alpine sh -c 'chown -R 1000:1000 /data || true'

# remove compiled views and re-chown, then run optimize as www
docker-compose -f docker-compose-multi-apps.yml exec app-siimut sh -c '
  rm -rf storage/framework/views/* 2>/dev/null || true
  chown -R 1000:1000 storage bootstrap/cache || true
  chmod -R ug+rwX storage bootstrap/cache || true
'
# Run artisan optimize as www (use UID 1000)
docker-compose -f docker-compose-multi-apps.yml exec --user 1000:1000 app-siimut php artisan optimize

docker-compose -f docker-compose-multi-apps.yml exec app-siimut sh -c '
  if command -v su-exec >/dev/null 2>&1; then
    su-exec www php artisan optimize
  else
    php artisan optimize
  fi
'