#!/bin/bash

# certs/common.sh - Certificate-specific common functions
# Functions specific to certificate generation and management

# Function to validate certificate-specific paths and dependencies
validate_cert_dependencies() {
    local dependencies=("openssl" "envsubst")
    local missing_deps=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        return 1
    fi
    
    return 0
}

# Function to create certificate-specific directories
initialize_cert_directories() {
    local cert_dirs=("/app/certs" "/app/config" "/app/templates/certificates")
    
    for dir in "${cert_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_debug "Certificate directory created: $dir"
        fi
    done
}

# Function to validate certificate template exists
validate_cert_template() {
    local cert_type="$1"
    local template_file="/app/templates/certificates/${cert_type}.conf.template"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "Certificate template not found: $template_file"
        return 1
    fi
    
    log_debug "Certificate template validated: $template_file"
    return 0
}

# Function to clean up temporary certificate files
cleanup_cert_temp_files() {
    local temp_files=("/tmp/cert_*.tmp" "/tmp/openssl_*.conf")
    
    for pattern in "${temp_files[@]}"; do
        rm -f $pattern 2>/dev/null || true
    done
    
    log_debug "Certificate temporary files cleaned up"
}

# Function to show generic help (moved from Init common.sh)
show_generic_help() {
    cat << EOL
ICBanking Init Container - Initialization System

Usage: $0 [ACTION] [OPTIONS]

Available actions:
  certificates    Generate SSL/TLS certificates
  help           Show this help
  version        Show container version

Global environment variables:
  DEBUG          Enable debug logs (true/false)
  
For specific action help, use:
  $0 [ACTION] --help

Examples:
  $0 certificates --help
  $0 certificates generate
  
📖 Complete documentation: See README.md
EOL
}

# Function to show version (moved from Init common.sh)
show_version() {
    cat << EOL
ICBanking Init Container v${VERSION:-1.0.0}
Built for SSL/TLS certificate generation and environment initialization
© $(date +%Y) Infocorp Group
EOL
}

# Function to check if a command/action exists (moved from Init common.sh)
action_exists() {
    local action="$1"
    local script_path="/app/scripts/${action}.sh"
    
    if [[ -f "$script_path" && -x "$script_path" ]]; then
        return 0
    else
        return 1
    fi
}

# Function to execute an action (moved from Init common.sh)
execute_action() {
    local action="$1"
    shift # Remove first argument (action) from array
    
    local script_path="/app/scripts/${action}.sh"
    
    if action_exists "$action"; then
        log_info "Executing action: $action"
        # Execute script passing all remaining arguments
        "$script_path" "$@"
    else
        log_error "Action not found: $action"
        log_error "Expected script at: $script_path"
        return 1
    fi
}

# Function to list available actions (moved from Init common.sh)
list_available_actions() {
    log_info "Available actions:"
    
    if [[ -d "/app/scripts" ]]; then
        for script in /app/scripts/*.sh; do
            if [[ -f "$script" ]]; then
                local action=$(basename "$script" .sh)
                echo "  - $action"
            fi
        done
    else
        log_warn "/app/scripts directory not found"
    fi
}

# Function for cleanup on exit (moved from Init common.sh)
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script finished with error code: $exit_code"
    else
        log_info "Script finished successfully"
    fi
}

# Configure trap for cleanup (moved from Init common.sh)
trap cleanup_on_exit EXIT
