FROM alpine:3.20

COPY ./scripts ./app
COPY certs-install.ps1 ./app/scripts/pwsh
COPY entrypoint.sh entrypoint.sh

# Make entrypoint executable
RUN chmod +x entrypoint.sh

# Set the entrypoint
ENTRYPOINT ["entrypoint.sh"]