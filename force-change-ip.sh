#!/bin/bash
echo "Mencari dan mengganti 127.0.0.1 dengan 192.168.1.9:7200 di dalam container fe-smsp..."
docker exec fe-smsp sh -c '
    count=$(grep -rl "127.0.0.1" /usr/share/nginx/html/assets/ | wc -l)
    if [ "$count" -eq 0 ]; then
        echo "✅ TIDAK ADA 127.0.0.1 yang ditemukan di server!"
        echo "✅ File JS di server SUDAH BERISI IP yang benar (192.168.1.9:7200)."
        echo "Lihat sendiri isinya:"
        grep -o ".\{0,30\}baseURL.\{0,30\}" /usr/share/nginx/html/assets/index-*.js | head -n 1
    else
        echo "Mengganti IP di $count file..."
        find /usr/share/nginx/html/assets/ -name "*.js" -exec sed -i "s/127\.0\.0\.1:7200/192.168.1.9:7200/g" {} \;
        echo "Selesai diganti!"
    fi
'
echo "Selesai mengecek container."
