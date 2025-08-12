
#!/bin/sh

# Importa funciones y utilidades necesarias
. /app/scripts/common.sh
. /app/scripts/certificates/utils.sh

# Recarga las variables de entorno desde /app/config/default.vars
reload_vars() {
    local vars_file="/app/config/default.vars"
    if [ -f "$vars_file" ]; then
        while IFS='=' read -r var val; do
            # Ignora líneas vacías y comentarios
            if [[ -z "$var" || "$var" =~ ^# ]]; then continue; fi
            var="$(echo "$var" | xargs)"
            # Recarga forzosa: sobrescribe cualquier valor existente
            export "$var"="$val"
        done < "$vars_file"
    fi
}

# Ejecuta la generación de certificados
generate_certs() {
    echo "[INFO] Ejecutando generación de certificados manual..."
    /app/scripts/certificates/certificates.sh "$@"
}
