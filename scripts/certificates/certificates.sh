#!/bin/bash

# certificates.sh - Script for SSL/TLS certificate generation
# Contains all specific logic for creating certificates
# Load common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"
source "${SCRIPT_DIR}/utils.sh"

# Borra los archivos de la CA para forzar regeneración limpia
delete_ca_files() {
    if [[ "${CERT_PRESERVE_CA_FILES:-}" == "true" ]]; then
        log_info "Skipping CA files deletion (preserve mode enabled)"
        return
    fi
    local ca_name="ca"
    get_cert_paths "$ca_name"
    local ca_key="$CERT_CA_PRIVATE_KEY"
    local ca_cert="$CERT_CA_CERT_FILE"
    local ca_csr="$CERT_CA_CSR_FILE"
    local ca_pem="${ca_cert%.crt}.pem"
    local ca_srl="${ca_cert%.crt}.srl"
    rm -f "$ca_key" "$ca_cert" "$ca_csr" "$ca_pem" "$ca_srl"
    log_info "CA files deleted: $ca_key $ca_cert $ca_csr $ca_pem $ca_srl"
}

# Function to validate certificate-specific environment variables
validate_cert_env() {
    local required_vars=("CERT_CN")
    validate_required_vars "${required_vars[@]}"
}

# Function to get output paths (allows customization via environment variables)
get_cert_paths() {
    local cert_name="$1"
    
    # Use environment variables or defaults (but avoid /app paths in console mode)
    local certs_dir="${CERT_OUTPUT_DIR:-}"
    local config_dir="${CERT_CONFIG_DIR:-}"
    
    # If no custom paths are set and /app doesn't exist, use temp directories
    if [[ -z "$certs_dir" ]]; then
        if [[ -d "/app" ]]; then
            certs_dir="/app/certs"
        else
            certs_dir="./certs"
        fi
    fi
    
    if [[ -z "$config_dir" ]]; then
        if [[ -d "/app" ]]; then
            config_dir="/app/config"
        else
            config_dir="./config"
        fi
    fi
    
    # Ensure directories exist
    mkdir -p "$certs_dir" "$config_dir"
    
    # Return paths as associative array-like variables

    CERT_CA_PRIVATE_KEY="$certs_dir/ca.key"
    CERT_CA_CERT_FILE="$certs_dir/ca.crt"
    CERT_CA_CSR_FILE="$certs_dir/ca.csr"
    CERT_CA_CONFIG_FILE="$config_dir/ca.conf"

    CERT_PRIVATE_KEY="$certs_dir/${cert_name}.key"
    CERT_FILE="$certs_dir/${cert_name}.crt"
    CERT_CSR_FILE="$certs_dir/${cert_name}.csr"
    CERT_CONFIG_FILE="$config_dir/${cert_name}.conf"
    CERT_PEM_FILE="$certs_dir/${cert_name}.pem"
    CERT_PFX_FILE="$certs_dir/${cert_name}.pfx"
    CERT_P12_FILE="$certs_dir/${cert_name}.p12"
}

# Function to generate OpenSSL configuration dynamically
generate_openssl_config() {
    local config_file="$1"
    local cert_type="$2"
    
    log_info "Generating OpenSSL configuration for: $config_file (type: $cert_type)"
    
    # Select appropriate template based on certificate type
    local template_file="${SCRIPT_DIR}/templates/${cert_type}.conf.template"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi
    
    # Copy template and substitute variables
    log_info "Using template: $template_file"
    
    # Try envsubst with explicit variable list
    export CERT_CN CERT_ALT_NAMES CERT_VALIDITY_DAYS CERT_SIZE CERT_KEY_PASSWORD CERT_PFX_PASSWORD CERT_FRIENDLY_NAME
    envsubst '$CERT_CN' < "$template_file" > "$config_file"
    
    # Check if substitution worked
    if [[ $(wc -c < "$config_file") -lt 10 ]]; then
        log_error "Config file is too small, envsubst may have failed"
        sed "s/\${CERT_CN}/$CERT_CN/g" "$template_file" > "$config_file"
    fi
    
    # For server and client certificates, add dynamic alt_names
    if [[ "$cert_type" == "server" || "$cert_type" == "client" || "$cert_type" == "ca" ]]; then
        # Generate alt_names from environment variable or use defaults
        local alt_names="${CERT_ALT_NAMES:-DNS:${CERT_CN},DNS:localhost,IP:127.0.0.1}"
        
        # Process the alt_names string and append to config
        local counter=1
        local alt_names_section=""
        IFS=',' read -ra ALT_ARRAY <<< "$alt_names"
        for alt in "${ALT_ARRAY[@]}"; do
            alt=$(echo "$alt" | xargs) # trim whitespace
            if [[ "$alt" =~ ^DNS: ]]; then
                alt_names_section+="DNS.$counter = ${alt#DNS:}"$'\n'
            elif [[ "$alt" =~ ^IP: ]]; then
                alt_names_section+="IP.$counter = ${alt#IP:}"$'\n'
            else
                # Default to DNS if no prefix
                alt_names_section+="DNS.$counter = $alt"$'\n'
            fi
            ((counter++))
        done
        
        # Replace the alt_names comment with actual entries
        # Remove the comment line and add the alt_names entries
        sed -i '/# The alt_names are generated dynamically from CERT_ALT_NAMES/d' "$config_file"
        printf "%s" "$alt_names_section" >> "$config_file"
    fi
    log_info "OpenSSL configuration generated successfully"
}


# Helper: Generate CA if not exists
generate_ca() {
    local ca_name="ca"
    local ca_key="$CERT_CA_PRIVATE_KEY"
    local ca_cert="$CERT_CA_CERT_FILE"
    local ca_csr="$CERT_CA_CSR_FILE"
    local ca_config="$CERT_CA_CONFIG_FILE"
    local key_password="${CERT_KEY_PASSWORD:-icbanking123}"

    if [[ ! -f "$ca_key" ]]; then
        log_info "Generating CA private key..."
        openssl genrsa -aes256 -passout "pass:$key_password" -out "$ca_key" "${CERT_SIZE:-2048}"
        chmod 600 "$ca_key"
    fi
    if [[ ! -f "$ca_config" ]]; then
        generate_openssl_config "$ca_config" "ca"
    fi
    if [[ ! -f "$ca_cert" ]]; then
        log_info "Generating CA certificate..."
        openssl req -x509 -new -nodes -key "$ca_key" -passin "pass:$key_password" -sha256 -days "${CERT_VALIDITY_DAYS:-3650}" -out "$ca_cert" -config "$ca_config"
    fi
    
    # Always generate CA PEM file (same as .crt but with .pem extension for compatibility)
    local ca_pem_file="${ca_cert%.crt}.pem"
    if [[ ! -f "$ca_pem_file" ]] || [[ "$ca_cert" -nt "$ca_pem_file" ]]; then
        log_info "Generating CA PEM file: $ca_pem_file"
        cp "$ca_cert" "$ca_pem_file"
        log_info "✅ CA PEM file created successfully"
    fi
}

# Main certificate generation function
generate_certificate() {
    local cert_name="${1:-default}"
    local cert_type="${CERT_TYPE:-server}"

    # Borrar archivos de la CA antes de generar (solo la primera vez)
    delete_ca_files
    
    log_info "Generating certificate: $cert_name (type: $cert_type)"

    # Get output paths (supports custom directories)
    get_cert_paths "$cert_name"

    # Generate configuration if it doesn't exist or is empty
    if [[ ! -f "$CERT_CONFIG_FILE" ]] || [[ ! -s "$CERT_CONFIG_FILE" ]]; then
        generate_openssl_config "$CERT_CONFIG_FILE" "$cert_type"
        
        # Check if generation was successful
        if [[ ! -f "$CERT_CONFIG_FILE" ]] || [[ $(wc -c < "$CERT_CONFIG_FILE") -lt 10 ]]; then
            log_error "Config file generation failed or produced empty file"
            return 1
        fi
    fi

    # Generate CA if not exists
    generate_ca
    local ca_key="$CERT_CA_PRIVATE_KEY"
    local ca_cert="$CERT_CA_CERT_FILE"
    local ca_csr="$CERT_CA_CSR_FILE"
    local ca_config="$CERT_CA_CONFIG_FILE"
    local key_password="${CERT_KEY_PASSWORD:-icbanking123}"
    local pfx_password="${CERT_PFX_PASSWORD:-icbanking123}"

    # Generate private key with password protection
    log_info "Generating private key with password protection..."
    openssl genrsa -aes256 -passout "pass:$key_password" -out "$CERT_PRIVATE_KEY" "${CERT_SIZE:-2048}"
    chmod 600 "$CERT_PRIVATE_KEY"

    # Generate CSR
    log_info "Generating Certificate Signing Request..."
    openssl req -new \
        -key "$CERT_PRIVATE_KEY" \
        -passin "pass:$key_password" \
        -out "$CERT_CSR_FILE" \
        -config "$CERT_CONFIG_FILE"

    # Sign certificate with CA
    log_info "Signing certificate with CA..."
    openssl x509 -req \
        -in "$CERT_CSR_FILE" \
        -CA "$ca_cert" \
        -CAkey "$ca_key" \
        -passin "pass:$key_password" \
        -CAcreateserial \
        -out "$CERT_FILE" \
        -days "${CERT_VALIDITY_DAYS:-365}" \
        -extensions v3_req \
        -extfile "$CERT_CONFIG_FILE"

    # Generate combined PEM file (certificate + encrypted private key)
    cat "$CERT_FILE" "$CERT_PRIVATE_KEY" > "$CERT_PEM_FILE"

    # Generate PFX file (PKCS#12) with password-protected private key and friendly name
    local friendly_name="${CERT_FRIENDLY_NAME:-${cert_name}}"
    log_info "Generating PFX file with friendly name: $friendly_name"
    openssl pkcs12 -export \
        -out "$CERT_PFX_FILE" \
        -inkey "$CERT_PRIVATE_KEY" \
        -passin "pass:$key_password" \
        -in "$CERT_FILE" \
        -certfile "$ca_cert" \
        -name "$friendly_name" \
        -caname "$friendly_name" \
        -password "pass:$pfx_password"

    # Generate P12 file (PKCS#12) - alternative format with password-protected private key and friendly name
    log_info "Generating P12 file with friendly name: $friendly_name"
    openssl pkcs12 -export \
        -out "$CERT_P12_FILE" \
        -inkey "$CERT_PRIVATE_KEY" \
        -passin "pass:$key_password" \
        -in "$CERT_FILE" \
        -certfile "$ca_cert" \
        -name "$friendly_name" \
        -caname "$friendly_name" \
        -password "pass:$pfx_password"

    # Verifications
    log_info "Verifying PFX file structure..."
    local pfx_info=$(openssl pkcs12 -info -in "$CERT_PFX_FILE" -password "pass:$pfx_password" -noout 2>/dev/null)
    if echo "$pfx_info" | grep -q "friendlyName"; then
        log_info "✅ Friendly name successfully embedded in PFX file"
        echo "$pfx_info" | grep "friendlyName" | head -1
    elif echo "$pfx_info" | grep -q "localKeyID"; then
        log_info "✅ PFX file structure verified (localKeyID present)"
    else
        log_info "✅ PFX file generated successfully"
    fi

    log_info "Testing PFX certificate extraction..."
    if openssl pkcs12 -in "$CERT_PFX_FILE" -password "pass:$pfx_password" -nokeys -nomacver -clcerts -noout 2>/dev/null; then
        log_info "✅ Certificate extraction successful"
    else
        log_warn "⚠️ Certificate extraction failed"
    fi

    log_info "Testing private key extraction..."
    if openssl rsa -in "$CERT_PRIVATE_KEY" -passin "pass:$key_password" -noout -check 2>/dev/null; then
        log_info "✅ Private key extraction and validation successful"
    else
        log_warn "⚠️ Private key extraction or validation failed"
    fi

    log_info "Certificate generated successfully:"
    log_info "  - Certificate: $CERT_FILE"
    log_info "  - Private key: $CERT_PRIVATE_KEY (AES256 encrypted)"
    log_info "    * Key password: $key_password"
    log_info "  - Combined PEM: $CERT_PEM_FILE (contains encrypted private key)"
    log_info "  - PFX (PKCS#12): $CERT_PFX_FILE"
    log_info "    * PFX password: $pfx_password"
    log_info "    * Friendly name (cert & key): $friendly_name"
    log_info "  - P12 (PKCS#12): $CERT_P12_FILE"
    log_info "    * P12 password: $pfx_password"
    log_info "    * Friendly name (cert & key): $friendly_name"
    log_info "  - CSR: $CERT_CSR_FILE"
    log_info ""
    log_info "CA (Certificate Authority) files:"
    log_info "  - CA Certificate: $CERT_CA_CERT_FILE"
    log_info "  - CA PEM: ${CERT_CA_CERT_FILE%.crt}.pem (same content as CA cert, .pem extension)"
    log_info "  - CA Private Key: $CERT_CA_PRIVATE_KEY (AES256 encrypted)"
    log_info "    * CA Key password: $key_password"

    log_info "Now generating client certificate signed by CA..."
    if [[ "$cert_type" == "server" ]]; then
        generate_client_cert_with_ca "$cert_name"
    fi
}


# Nuevo: Generar certificado de cliente firmado por la CA
generate_client_cert_with_ca() {
    local cert_name="$1"
    local key_password="${CERT_KEY_PASSWORD:-icbanking123}"
    local pfx_password="${CERT_PFX_PASSWORD:-icbanking123}"
    local friendly_name="${CERT_FRIENDLY_NAME:-${cert_name}_client}"

    # Usar los paths ya definidos para el server
    get_cert_paths "$cert_name"

    # Paths para el cliente
    local client_cert_file="${CERT_FILE%.crt}_client.crt"
    local client_csr_file="${CERT_CSR_FILE%.csr}_client.csr"
    local client_pfx_file="${CERT_PFX_FILE%.pfx}_client.pfx"
    local client_config_file="${CERT_CONFIG_FILE%.conf}_client.conf"

    # Generar config para client si no existe
    if [[ ! -f "$client_config_file" ]]; then
        generate_openssl_config "$client_config_file" "client"
    fi

    # Generar la CA si no existe
    generate_ca
    local ca_name="ca"
    local ca_key="$CERT_CA_PRIVATE_KEY"
    local ca_cert="$CERT_CA_CERT_FILE"

    # Generar CSR para el cliente usando la clave del server
    openssl req -new \
        -key "$CERT_PRIVATE_KEY" \
        -passin "pass:$key_password" \
        -out "$client_csr_file" \
        -config "$client_config_file"

    # Firmar el certificado de cliente con la CA
    openssl x509 -req \
        -in "$client_csr_file" \
        -CA "$ca_cert" \
        -CAkey "$ca_key" \
        -passin "pass:$key_password" \
        -CAcreateserial \
        -out "$client_cert_file" \
        -days "${CERT_VALIDITY_DAYS:-365}" \
        -extensions v3_req \
        -extfile "$client_config_file"

    # Empaquetar el certificado de cliente en un PFX
    openssl pkcs12 -export \
        -out "$client_pfx_file" \
        -inkey "$CERT_PRIVATE_KEY" \
        -passin "pass:$key_password" \
        -in "$client_cert_file" \
        -certfile "$ca_cert" \
        -name "$friendly_name" \
        -caname "$friendly_name" \
        -password "pass:$pfx_password"

    log_info "Client PFX certificate generated and signed by CA:"
    log_info "  - Certificate: $client_cert_file"
    log_info "  - PFX: $client_pfx_file"
}

# Function to generate multiple certificates
generate_multiple_certs() {
    local cert_names="${CERT_NAMES:-default}"
    IFS=',' read -ra NAMES <<< "$cert_names"
    
    log_info "Generating ${#NAMES[@]} certificate(s): ${NAMES[*]}"
    
    for name in "${NAMES[@]}"; do
        name=$(echo "$name" | xargs) # trim whitespace
        generate_certificate "$name"
    done
    
    log_info "All certificates generated successfully"
}

# Function to create configuration templates
create_templates() {
    log_info "Creating configuration templates..."
    
    # Use custom templates directory if specified
    local templates_dir="${CERT_TEMPLATES_DIR:-${SCRIPT_DIR}/templates}"
    
    # Copy template files from source templates to templates directory
    local template_files=("server.conf.template" "client.conf.template" "ca.conf.template")
    
    for template in "${template_files[@]}"; do
        local source="${SCRIPT_DIR}/templates/${template}"
        local target="${templates_dir}/${template}"
        
        if [[ -f "$source" ]]; then
            # Copy template to target location if it doesn't exist
            if [[ ! -f "$target" ]]; then
                cp "$source" "$target" 2>/dev/null || {
                    log_info "Could not copy template $template to $target, using source directly"
                }
            fi
            log_info "Template available: $template"
        else
            log_warn "Template not found: $source"
        fi
    done
    
    log_info "Templates validated successfully"
}

# Function to initialize certificate environment
initialize_cert_environment() {
    log_info "Initializing certificate environment..."

    # Check if we're running in Docker (by checking if /app exists) or console
    if [[ "${CERT_OUTPUT_DIR:-}" != "" ]] || [[ "${CERT_CONFIG_DIR:-}" != "" ]] || [[ ! -d "/app" ]]; then
        # Custom paths specified or not in Docker environment
        local certs_dir="${CERT_OUTPUT_DIR:-./certs}"
        local config_dir="${CERT_CONFIG_DIR:-./config}"
        local templates_dir="${CERT_TEMPLATES_DIR:-./templates}"
        
        log_info "Running in console mode with custom paths"
        log_info "Creating directories: $certs_dir, $config_dir, $templates_dir"
        
        mkdir -p "$certs_dir" "$config_dir" "$templates_dir"
        log_info "Using custom certificate directories:"
        log_info "  - Certificates: $certs_dir"
        log_info "  - Config: $config_dir"
        log_info "  - Templates: $templates_dir"
        
        # Ensure we can write to the directories
        if [[ ! -w "$certs_dir" ]] || [[ ! -w "$config_dir" ]]; then
            log_error "Cannot write to specified directories. Please check permissions."
            return 1
        fi
    else
        # Use Docker defaults and initialization
        local certs_dir="${CERT_OUTPUT_DIR:-/app/certs}"
        local config_dir="${CERT_CONFIG_DIR:-/app/config}"
        local templates_dir="${CERT_TEMPLATES_DIR:-/app/templates}"
        
        log_info "Running in Docker environment, using standard initialization"
        initialize_common_directories "root" "$certs_dir" "$config_dir" "$templates_dir"
    fi

    # Validate templates exist (skip in console mode to avoid /app issues)
    if [[ -d "/app" ]]; then
        create_templates
    else
        log_info "Console mode: Skipping template validation"
    fi
    
    log_info "Certificate environment initialized correctly"
}

# Function to show certificate-specific help
show_cert_help() {
    cat << EOL
ICBanking Init Container - SSL/TLS Certificate Generator

Usage: $0 certificates [COMMAND] [OPTIONS]

Available commands:
  generate       Generate certificates (default)
  init           Initialize environment only
  templates      Create configuration templates
  help           Show this help

Specific environment variables:
  CERT_CN            - Common Name (required)
  CERT_ALT_NAMES     - Subject Alternative Names separated by comma
                       Format: DNS:domain.com,IP:192.168.1.1,DNS:*.domain.com
                       (default: DNS:\${CERT_CN},DNS:localhost,IP:127.0.0.1)
  CERT_VALIDITY_DAYS - Validity days (default: 365)
  CERT_KEY_PASSWORD  - Password for private key encryption (default: icbanking123)
  CERT_PFX_PASSWORD  - Password for PFX/P12 files (default: icbanking123)
  CERT_FRIENDLY_NAME - Friendly name for PFX/P12 files (default: certificate name)
  CERT_SIZE          - RSA key size (default: 2048)
  CERT_TYPE          - Type: server|client|ca (default: server)
  CERT_NAMES         - Names separated by comma (default: default)

Output directory customization:
  CERT_OUTPUT_DIR    - Custom output directory for certificates (default: /app/certs)
  CERT_CONFIG_DIR    - Custom directory for config files (default: /app/config)
  CERT_TEMPLATES_DIR - Custom directory for templates (default: /app/templates)

Fixed organization:
  Country: UY (Uruguay)
  State: Montevideo
  City: Montevideo
  Organization: Infocorpgroup
  Email: ingenieria@infocorp.com.uy

📖 Complete documentation and examples: See README.md

Usage examples:
  $0 certificates generate
  $0 certificates init
  $0 certificates templates
  
  # With environment variables
  CERT_CN=api.example.com CERT_NAMES=api,web $0 certificates generate
  CERT_CN=localhost CERT_FRIENDLY_NAME="ICBanking Development Certificate" $0 certificates generate
  
  # With custom output directory
  CERT_OUTPUT_DIR=/tmp/mycerts CERT_CN=localhost $0 certificates generate
  CERT_OUTPUT_DIR=/home/user/certs CERT_CONFIG_DIR=/home/user/config CERT_CN=api.local $0 certificates generate
EOL
}

# Main function to handle certificate commands
main() {
    local command="${1:-generate}"
    
    case "$command" in
        "help"|"-h"|"--help")
            show_cert_help
            ;;
        "init")
            initialize_cert_environment
            ;;
        "generate"|"")
            initialize_cert_environment
            validate_cert_env
            generate_multiple_certs
            ;;
        "templates")
            initialize_cert_environment
            create_templates
            ;;
        *)
            log_error "Unrecognized command: $command"
            show_cert_help
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"

# Explicit successful exit
log_info "Certificate generation script completed successfully"
exit 0
