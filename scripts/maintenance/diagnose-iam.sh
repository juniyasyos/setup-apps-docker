#!/bin/bash

echo "=================================="
echo "IAM SSO REDIRECT LOOP DIAGNOSTICS"
echo "=================================="
echo "Timestamp: $(date)"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== 1. CONTAINER STATUS ===${NC}"
docker compose -f docker-compose-multi-apps.yml ps app-iam | tail -2
echo ""

echo -e "${YELLOW}=== 2. ENV FILE CONTENTS (.env.iam) ===${NC}"
if [ -f "env/.env.iam" ]; then
    cat env/.env.iam
else
    echo "❌ env/.env.iam not found"
fi
echo ""

echo -e "${YELLOW}=== 3. APP_URL & IAM_ISSUER IN CONTAINER ===${NC}"
docker compose -f docker-compose-multi-apps.yml exec -T app-iam env | grep -E "APP_URL|IAM_ISSUER|APP_ENV|TRUSTED" || echo "❌ Failed to get env vars"
echo ""

echo -e "${YELLOW}=== 4. CONFIG(IAM.ISSUER) VIA ARTISAN TINKER ===${NC}"
docker compose -f docker-compose-multi-apps.yml exec -T app-iam php artisan tinker <<EOF 2>&1 | head -50
config('iam.issuer')
config('app.url')
exit
EOF
echo ""

echo -e "${YELLOW}=== 5. VERIFY ENDPOINT TEST ===${NC}"
echo "Testing: GET http://192.168.1.4:8000/api/sso/verify"
docker compose -f docker-compose-multi-apps.yml exec -T app-iam curl -s http://192.168.1.4:8000/api/sso/verify -H "Authorization: Bearer invalid" 2>&1 | head -20
echo ""

echo -e "${YELLOW}=== 6. RECENT CONTAINER LOGS (last 50 lines) ===${NC}"
docker compose -f docker-compose-multi-apps.yml logs app-iam --tail=50 2>&1
echo ""

echo -e "${YELLOW}=== 7. NGINX LOGS - ERROR (last 20 lines) ===${NC}"
docker compose -f docker-compose-multi-apps.yml logs web --tail=20 2>&1 | grep -i "redirect\|error\|sso" || echo "No relevant logs found"
echo ""

echo -e "${YELLOW}=== 8. CHECK SIIMUT CONFIG ===${NC}"
docker compose -f docker-compose-multi-apps.yml exec -T app-siimut php artisan tinker <<EOF 2>&1 | head -30
config('iam.issuer')
config('iam.host')
config('iam.base_url')
exit
EOF
echo ""

echo -e "${YELLOW}=== 9. TRUSTED_PROXIES CHECK ===${NC}"
docker compose -f docker-compose-multi-apps.yml exec -T app-iam php artisan tinker <<EOF 2>&1
config('trustedproxy.proxies')
getenv('TRUSTED_PROXIES')
exit
EOF
echo ""

echo -e "${YELLOW}=== 10. NGINX MULTI-APPS CONFIG (first 100 lines) ===${NC}"
docker compose -f docker-compose-multi-apps.yml exec -T web cat /etc/nginx/conf.d/default.conf 2>&1 | head -100
echo ""

echo -e "${YELLOW}=== 11. DATABASE - APPLICATIONS TABLE ===${NC}"
docker compose -f docker-compose-multi-apps.yml exec -T database-service mysql -u root -proot_password siimut_db -e "SELECT id, key, name, redirect_uris FROM applications WHERE key='siimut' LIMIT 1;" 2>&1
echo ""

echo -e "${GREEN}=== DIAGNOSTICS COMPLETE ===${NC}"
echo "Please send the complete output above."

