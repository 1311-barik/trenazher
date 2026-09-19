#!/bin/zsh
# Выкладка на сервер: сборка веб-приложения + код синхронизации. Запуск с Mac: ./deploy/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/.."
SERVER=root@135.181.197.13
SSH=(ssh -i ~/.ssh/familybot)

(cd web-app && npm run build)
rsync -az --delete -e "ssh -i $HOME/.ssh/familybot" web-app/dist/ "$SERVER:/var/www/trenazher/app/"
rsync -az --delete --exclude tests --exclude __pycache__ -e "ssh -i $HOME/.ssh/familybot" content-sync/ "$SERVER:/opt/trenazher/content-sync/"
rsync -az -e "ssh -i $HOME/.ssh/familybot" deploy/ "$SERVER:/opt/trenazher/deploy/"
"${SSH[@]}" "$SERVER" 'install -m 755 /opt/trenazher/deploy/trenazher-set-key /usr/local/bin/trenazher-set-key && chown -R www-data:www-data /var/www/trenazher/app'
echo "Выложено: https://trenazher-135-181-197-13.nip.io"
