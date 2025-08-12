#!/bin/bash
# entrypoint.sh - Main entry point for ICBanking Init container
# Handles multiple actions and can be extended for future functionalities

# Load variables from /app/config/default.vars if not exist
load_default_vars_if_unset() {
    local vars_file="/app/config/default.vars"
    if [ -f "$vars_file" ]; then
        while IFS='=' read -r var val; do
            # Ignore empty lines and comments
            if [[ -z "$var" || "$var" =~ ^# ]]; then continue; fi
            var="$(echo "$var" | xargs)"
            val="$(echo "$val" | xargs)"
            if [ -z "${!var-}" ]; then
                export "$var"="$val"
                log_warn "$var=$val"
            fi
        done < "$vars_file"
    fi
}

# Load common functions
source /app/scripts/common.sh
source /app/scripts/certificates/utils.sh

# Handle signals gracefully
trap 'log_info "Script completed normally"; exit 0' EXIT
trap 'log_info "Script interrupted by signal"; exit 0' SIGTERM SIGINT SIGQUIT

# Main entrypoint function
main() {
    log_info "Starting main entrypoint"
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