#!/bin/bash

# common.sh - Common functions used by all scripts
# Logging functions, validation and general utilities

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

# Function to validate required environment variables
validate_required_vars() {
    local required_vars=("$@")
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Required environment variables not defined: ${missing_vars[*]}"
        return 1
    fi
    
    return 0
}

# Function to initialize common directories
# Usage: initialize_common_directories user directory1 [directory2] ...
# Requires user and at least one directory to be provided
initialize_common_directories() {
    log_info "Initializing common directories..."
    
    local user="$1"
    shift # Remove user from arguments
    local dirs=("$@")
    
    # Check if user is provided
    if [[ -z "$user" ]]; then
        log_error "No user provided. Usage: initialize_common_directories user directory1 [directory2] ..."
        return 1
    fi
    
    # Check if at least one directory is provided
    if [[ ${#dirs[@]} -eq 0 ]]; then
        log_error "No directories provided. Usage: initialize_common_directories user directory1 [directory2] ..."
        return 1
    fi
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            log_debug "Directory created: $dir"
        else
            log_debug "Directory already exists: $dir"
        fi
        
        # If we're running as root, fix ownership immediately
        if [[ "$(id -u)" -eq 0 ]]; then
            chown -R "$user:$user" "$dir"
            log_debug "Fixed ownership as root for: $dir"
        fi
    done
    
    # Ensure correct permissions on directories
    # Apply general permissions to all provided directories
    for dir in "${dirs[@]}"; do
        # Try to change ownership, but don't fail if it doesn't work (might be volume)
        if [[ "$(id -u)" -ne 0 ]]; then
            chown -R "$user:$user" "$dir" 2>/dev/null || {
                log_warn "Could not change ownership of $dir (might be mounted volume)"
            }
        fi
        
        # Set restrictive permissions for private directories
        if [[ "$dir" == *"private"* ]]; then
            chmod 700 "$dir" 2>/dev/null || {
                log_warn "Could not set permissions on private directory: $dir"
            }
        else
            chmod 755 "$dir" 2>/dev/null || {
                log_warn "Could not set permissions on directory: $dir"
            }
        fi
        
        # Test write permissions
        local test_file="${dir}/.write_test_$$"
        if touch "$test_file" 2>/dev/null; then
            rm -f "$test_file"
            log_debug "Write permissions confirmed for: $dir"
        else
            log_warn "No write permissions for directory: $dir"
            log_warn "Current user: $(whoami), Directory permissions: $(ls -ld "$dir" 2>/dev/null || echo 'unknown')"
            
            # If we can't write to the directory, try to create it in a user-writable location
            if [[ "$dir" == "/app/config" ]]; then
                local user_config_dir="/tmp/config"
                mkdir -p "$user_config_dir"
                log_warn "Using fallback config directory: $user_config_dir"
                # We could set an environment variable here for scripts to use
                export CERT_CONFIG_PATH="$user_config_dir"
            elif [[ "$dir" == "/app/templates" ]]; then
                local user_templates_dir="/tmp/templates"
                mkdir -p "$user_templates_dir"
                log_warn "Using fallback templates directory: $user_templates_dir"
            else
                log_error "Cannot proceed without write access to: $dir"
                return 1
            fi
        fi
    done
    
    log_info "Base directories initialized correctly"
}

