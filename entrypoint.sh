#!/bin/bash

# Handles multiple actions and can be extended for future functionalities

set -euo pipefail

# Load common functions
source /app/scripts/common.sh
source /app/scripts/certificates/utils.sh

# Main entrypoint function
main() {
    local action="${1:-default}"

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
            generate_certificates
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
