FROM alpine:3.20

RUN apk add --no-cache bash dos2unix gettext openssl

COPY scripts/ ./app/scripts
COPY certs-install.ps1 ./app/scripts/pwsh/
COPY default.vars ./app/config/default.vars
COPY entrypoint.sh ./app/entrypoint.sh

# Keep a backup copy of default.vars and convert line endings
RUN cp ./app/config/default.vars /tmp/default.vars && \
    dos2unix ./app/entrypoint.sh

# Copia el script global_utils.sh para que se cargue en cada shell
COPY scripts/global_utils.sh /etc/profile.d/global_utils.sh

# Make entrypoint executable
RUN chmod +x /app/entrypoint.sh

VOLUME [ "/app/config", "/app/certs" ]

# Set the entrypoint
ENTRYPOINT ["./app/entrypoint.sh"]