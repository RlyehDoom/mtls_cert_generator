#!/bin/bash
# entrypoint.sh - Main entry point for ICBanking Init container
# Handles multiple actions and can be extended for future functionalities

# Load common functions
source /app/scripts/common.sh
source /app/scripts/certificates/utils.sh

# Handle signals gracefully
trap 'log_info "Script completed normally"; exit 0' EXIT
trap 'log_info "Script interrupted by signal"; exit 0' SIGTERM SIGINT SIGQUIT

# Load variables from /app/vars/default.vars if not exist
load_default_vars_if_unset() {
    local vars_file="/app/vars/default.vars"
    if [ -f "$vars_file" ]; then
        log_info "Loading variables from $vars_file"
        while IFS='=' read -r var val; do
            # Ignore empty lines and comments
            if [[ -z "$var" || "$var" =~ ^# ]]; then continue; fi
            var="$(echo "$var" | xargs)"
            val="$(echo "$val" | xargs)"
            # Check if variable is unset or empty
            if [[ -z "${!var:-}" ]]; then
                export "$var"="$val"
                log_warn "$var=$val"
            else
                log_info "Skipping $var (already set to: '${!var}')"
            fi
        done < "$vars_file"
    else
        log_error "Variables file not found: $vars_file"
    fi
}

# Clean directories function
clean_app_directories() {
    log_info "Cleaning application directories..."
    
    # Remove and recreate /app/config directory (preserving volume mount)
    if [[ -d "/app/config" ]]; then
        log_info "Cleaning /app/config directory contents"
        rm -rf /app/config/*
    else
        log_info "Creating /app/config directory"
        mkdir -p /app/config
    fi
    
    # Remove and recreate /app/certs directory (preserving volume mount)
    if [[ -d "/app/certs" ]]; then
        log_info "Cleaning /app/certs directory contents"
        rm -rf /app/certs/*
    else
        log_info "Creating /app/certs directory"
        mkdir -p /app/certs
    fi
    
    # Ensure /app/vars directory exists
    if [[ ! -d "/app/vars" ]]; then
        log_info "Creating /app/vars directory"
        mkdir -p /app/vars
    fi
    
    # Copy default.vars only if it doesn't exist (preserve existing configuration)
    if [[ ! -f "/app/vars/default.vars" ]]; then
        if [[ -f "/tmp/default.vars" ]]; then
            log_info "Copying default.vars from image to /app/vars/ (first time setup)"
            cp /tmp/default.vars /app/vars/default.vars
        else
            log_warn "default.vars not found in image, will use environment variables only"
        fi
    else
        log_info "Preserving existing /app/vars/default.vars (not overwriting)"
    fi
    
    log_info "Directory cleanup completed"
}

# Main entrypoint function
main() {
    log_info "Starting main entrypoint"
    
    # Always clean directories at startup
    clean_app_directories
    
    local action="${1:-default}"
    load_default_vars_if_unset

    # Process action
    case "$action" in
        "certificates")
            shift # Remove 'certificates' from arguments
            generate_certificates "$@"
            ;;
        "help"|"-h"|"--help")
            show_generic_help
            ;;
        "version"|"-v"|"--version")
            show_version
            ;;
        "list"|"ls")
            list_available_actions
            ;;
        "default")
            shift # Remove 'default' from arguments
            generate_certificates "$@"
            ;;
        *)
            # Try to execute as custom action
            if action_exists "$action"; then
                shift # Remove action from arguments
                execute_action "$action" "$@"
            else
                log_error "Unrecognized action: $action"
                echo ""
                show_generic_help
                echo ""
                list_available_actions
                exit 1
            fi
            ;;
    esac
    
    # Finally block - always executes regardless of which case was processed
    finally_block
}

# Finally block that always executes at the end
finally_block() {

    log_info "Container will remain open for inspection and additional operations"
    log_info "To exit, use Ctrl+C or 'docker stop <container_id>'"
    
    # Run an infinite loop to keep container alive
    tail -f /dev/null
}

generate_certificates() {
    # Check if certificate generation is enabled
    if [[ "${GENERATE_CERTIFICATES:-true}" == "true" ]]; then
        log_info "Executing certificate generation..."
        /app/scripts/certificates/certificates.sh "$@"
    else
        log_info "Certificate generation disabled via GENERATE_CERTIFICATES=false"
        log_info "To enable, set GENERATE_CERTIFICATES=true"
    fi
}

# Check if running directly or being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Execute main function
    if [[ $# -eq 0 ]]; then
        # No arguments, default action
        main "default"
    else
        # With arguments, process command
        main "$@"
    fi
fi