FROM adguard/adguardhome

RUN apk add --no-cache apache2-utils

COPY entrypoint.sh /opt/adguardhome/entrypoint.sh
COPY AdGuardHome.yaml.template /opt/adguardhome/conf/AdGuardHome.yaml.template

RUN chmod +x /opt/adguardhome/entrypoint.sh

ENTRYPOINT ["/opt/adguardhome/entrypoint.sh"]
