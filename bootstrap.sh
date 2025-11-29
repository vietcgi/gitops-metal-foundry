#!/usr/bin/env bash
#
# GitOps Metal Foundry - Bootstrap Script
#
# Run from your local machine (Mac/Linux) with OCI CLI and GitHub CLI installed.
# This script:
#   1. Creates OCI API key for GitHub Actions
#   2. Sets GitHub secrets via `gh` CLI (no manual steps!)
#   3. Creates terraform.tfvars and pushes to repo
#
# Prerequisites:
#   - OCI CLI configured: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm
#   - GitHub CLI authenticated: gh auth login
#
# Usage:
#   ./bootstrap.sh
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Logging
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

banner() {
    echo -e "${CYAN}"
    cat << 'EOF'

   ╔═══════════════════════════════════════════════════════════════════╗
   ║                                                                   ║
   ║   ██████╗ ██╗████████╗ ██████╗ ██████╗ ███████╗                  ║
   ║  ██╔════╝ ██║╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝                  ║
   ║  ██║  ███╗██║   ██║   ██║   ██║██████╔╝███████╗                  ║
   ║  ██║   ██║██║   ██║   ██║   ██║██╔═══╝ ╚════██║                  ║
   ║  ╚██████╔╝██║   ██║   ╚██████╔╝██║     ███████║                  ║
   ║   ╚═════╝ ╚═╝   ╚═╝    ╚═════╝ ╚═╝     ╚══════╝                  ║
   ║                                                                   ║
   ║   ███╗   ███╗███████╗████████╗ █████╗ ██╗                        ║
   ║   ████╗ ████║██╔════╝╚══██╔══╝██╔══██╗██║                        ║
   ║   ██╔████╔██║█████╗     ██║   ███████║██║                        ║
   ║   ██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██║                        ║
   ║   ██║ ╚═╝ ██║███████╗   ██║   ██║  ██║███████╗                   ║
   ║   ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝                   ║
   ║                                                                   ║
   ║   ███████╗ ██████╗ ██╗   ██╗███╗   ██╗██████╗ ██████╗ ██╗   ██╗  ║
   ║   ██╔════╝██╔═══██╗██║   ██║████╗  ██║██╔══██╗██╔══██╗╚██╗ ██╔╝  ║
   ║   █████╗  ██║   ██║██║   ██║██╔██╗ ██║██║  ██║██████╔╝ ╚████╔╝   ║
   ║   ██╔══╝  ██║   ██║██║   ██║██║╚██╗██║██║  ██║██╔══██╗  ╚██╔╝    ║
   ║   ██║     ╚██████╔╝╚██████╔╝██║ ╚████║██████╔╝██║  ██║   ██║     ║
   ║   ╚═╝      ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝╚═════╝ ╚═╝  ╚═╝   ╚═╝     ║
   ║                                                                   ║
   ╚═══════════════════════════════════════════════════════════════════╝

EOF
    echo -e "${NC}"
    echo -e "   ${BOLD}Bare Metal Cloud on Oracle Free Tier${NC}"
    echo -e "   ${BOLD}Powered by: Tinkerbell + K3s + Cilium + Flux${NC}"
    echo ""
    echo -e "   ${GREEN}Cost: \$0.00/month (Always Free Tier)${NC}"
    echo ""
}

#=============================================================================
# Step 1: Validate Prerequisites
#=============================================================================

validate_prerequisites() {
    log_info "Validating prerequisites..."

    # Check required tools
    local missing=()
    for cmd in oci gh jq git openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  brew install oci-cli gh jq git openssl"
        exit 1
    fi
    log_success "All tools installed"

    # Check OCI CLI authentication
    if ! oci iam region list &> /dev/null; then
        log_error "OCI CLI not authenticated"
        echo ""
        echo "Run: oci setup config"
        exit 1
    fi
    log_success "OCI CLI authenticated"

    # Check GitHub CLI authentication
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI not authenticated"
        echo ""
        echo "Run: gh auth login"
        exit 1
    fi
    log_success "GitHub CLI authenticated"
}

#=============================================================================
# Step 2: Get OCI Configuration from CLI
#=============================================================================

get_oci_config() {
    log_info "Reading OCI configuration..."

    # Read from OCI CLI config file
    OCI_CONFIG_FILE="${OCI_CLI_CONFIG_FILE:-$HOME/.oci/config}"
    OCI_PROFILE="${OCI_CLI_PROFILE:-DEFAULT}"

    if [[ ! -f "$OCI_CONFIG_FILE" ]]; then
        log_error "OCI config file not found: $OCI_CONFIG_FILE"
        exit 1
    fi

    # Parse config file for the profile
    parse_oci_config() {
        local key=$1
        awk -v profile="[$OCI_PROFILE]" -v key="$key" '
            $0 == profile { found=1; next }
            /^\[/ { found=0 }
            found && $0 ~ "^"key"[[:space:]]*=" {
                sub(/^[^=]*=[[:space:]]*/, "")
                print
                exit
            }
        ' "$OCI_CONFIG_FILE"
    }

    OCI_USER=$(parse_oci_config "user")
    OCI_TENANCY=$(parse_oci_config "tenancy")
    OCI_REGION=$(parse_oci_config "region")
    OCI_KEY_FILE=$(parse_oci_config "key_file")

    # Expand ~ in key file path
    OCI_KEY_FILE="${OCI_KEY_FILE/#\~/$HOME}"

    if [[ -z "$OCI_USER" || -z "$OCI_TENANCY" || -z "$OCI_REGION" ]]; then
        log_error "Could not parse OCI config. Check your ~/.oci/config"
        exit 1
    fi

    log_success "User: ${OCI_USER:0:30}..."
    log_success "Tenancy: ${OCI_TENANCY:0:30}..."
    log_success "Region: $OCI_REGION"
}

#=============================================================================
# Step 3: Get GitHub Repository
#=============================================================================

get_github_repo() {
    echo ""
    log_info "GitHub Repository Configuration"

    # Try to detect from current directory
    if git remote get-url origin &> /dev/null; then
        DETECTED_REPO=$(git remote get-url origin | sed 's|.*github.com[:/]||' | sed 's|\.git$||')
        log_info "Detected repo: $DETECTED_REPO"
        read -r -p "Use this repo? (Y/n): " use_detected
        if [[ ! "$use_detected" =~ ^[Nn]$ ]]; then
            GITHUB_REPO_FULL="$DETECTED_REPO"
        fi
    fi

    if [[ -z "${GITHUB_REPO_FULL:-}" ]]; then
        read -r -p "Enter GitHub repo (owner/repo): " GITHUB_REPO_FULL
    fi

    # Parse owner/repo
    GITHUB_REPO_FULL=$(echo "$GITHUB_REPO_FULL" | sed 's|https://github.com/||' | sed 's|\.git$||' | sed 's|/$||')
    GITHUB_OWNER=$(echo "$GITHUB_REPO_FULL" | cut -d'/' -f1)
    GITHUB_REPO=$(echo "$GITHUB_REPO_FULL" | cut -d'/' -f2)

    if [[ -z "$GITHUB_OWNER" || -z "$GITHUB_REPO" ]]; then
        log_error "Invalid repo format. Use: owner/repo"
        exit 1
    fi

    # Verify repo exists and we have access
    if ! gh repo view "$GITHUB_OWNER/$GITHUB_REPO" &> /dev/null; then
        log_error "Cannot access repo: $GITHUB_OWNER/$GITHUB_REPO"
        exit 1
    fi

    log_success "GitHub repo: $GITHUB_OWNER/$GITHUB_REPO"
}

#=============================================================================
# Step 4: Create OCI API Key for GitHub Actions
#=============================================================================

create_api_key() {
    log_info "Setting up OCI API key for GitHub Actions..."

    API_KEY_DIR="$HOME/.oci/github-actions"
    API_KEY_FILE="$API_KEY_DIR/oci_api_key.pem"
    API_KEY_PUBLIC="$API_KEY_DIR/oci_api_key_public.pem"

    # Check if we already have a key
    if [[ -f "$API_KEY_FILE" ]]; then
        log_info "Found existing API key: $API_KEY_FILE"
        read -r -p "Use existing key? (Y/n): " use_existing
        if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
            # Get fingerprint of existing key
            OCI_FINGERPRINT=$(openssl rsa -pubout -in "$API_KEY_FILE" 2>/dev/null | openssl md5 -c | awk '{print $2}')
            OCI_KEY_CONTENT=$(cat "$API_KEY_FILE")
            log_success "Using existing API key"
            return
        fi
    fi

    # Create new key
    log_info "Generating new API key..."
    mkdir -p "$API_KEY_DIR"
    chmod 700 "$API_KEY_DIR"

    # Generate RSA 2048-bit key (OCI requirement)
    openssl genrsa -out "$API_KEY_FILE" 2048 2>/dev/null
    chmod 600 "$API_KEY_FILE"

    # Extract public key
    openssl rsa -pubout -in "$API_KEY_FILE" -out "$API_KEY_PUBLIC" 2>/dev/null

    # Calculate fingerprint
    OCI_FINGERPRINT=$(openssl rsa -pubout -in "$API_KEY_FILE" 2>/dev/null | openssl md5 -c | awk '{print $2}')
    OCI_KEY_CONTENT=$(cat "$API_KEY_FILE")

    log_success "Generated API key with fingerprint: $OCI_FINGERPRINT"

    # Upload public key to OCI
    log_info "Uploading public key to OCI..."

    # Check if key with this fingerprint already exists
    EXISTING_KEY=$(oci iam user api-key list \
        --user-id "$OCI_USER" \
        --query "data[?fingerprint=='$OCI_FINGERPRINT'].fingerprint | [0]" \
        --raw-output 2>/dev/null || echo "")

    if [[ -n "$EXISTING_KEY" && "$EXISTING_KEY" != "null" ]]; then
        log_info "API key already registered in OCI"
    else
        oci iam user api-key upload \
            --user-id "$OCI_USER" \
            --key-file "$API_KEY_PUBLIC" > /dev/null 2>&1 && \
            log_success "Uploaded API key to OCI" || \
            log_error "Failed to upload API key. You may need to add it manually in OCI Console."
    fi
}

#=============================================================================
# Step 5: Set GitHub Secrets
#=============================================================================

set_github_secrets() {
    log_info "Setting GitHub secrets via gh CLI..."

    # Set OCI secrets
    echo "$OCI_KEY_CONTENT" | gh secret set OCI_CLI_KEY_CONTENT -R "$GITHUB_OWNER/$GITHUB_REPO"
    log_success "Set secret: OCI_CLI_KEY_CONTENT"

    gh secret set OCI_CLI_USER -R "$GITHUB_OWNER/$GITHUB_REPO" -b "$OCI_USER"
    log_success "Set secret: OCI_CLI_USER"

    gh secret set OCI_CLI_TENANCY -R "$GITHUB_OWNER/$GITHUB_REPO" -b "$OCI_TENANCY"
    log_success "Set secret: OCI_CLI_TENANCY"

    gh secret set OCI_CLI_FINGERPRINT -R "$GITHUB_OWNER/$GITHUB_REPO" -b "$OCI_FINGERPRINT"
    log_success "Set secret: OCI_CLI_FINGERPRINT"

    gh secret set OCI_CLI_REGION -R "$GITHUB_OWNER/$GITHUB_REPO" -b "$OCI_REGION"
    log_success "Set secret: OCI_CLI_REGION"

    log_success "All GitHub secrets configured!"
}

#=============================================================================
# Step 6: Create Compartment
#=============================================================================

create_compartment() {
    log_info "Setting up OCI compartment..."

    PROJECT_NAME="${PROJECT_NAME:-metal-foundry}"

    EXISTING=$(oci iam compartment list \
        --compartment-id "$OCI_TENANCY" \
        --query "data[?name=='${PROJECT_NAME}' && \"lifecycle-state\"=='ACTIVE'].id | [0]" \
        --raw-output 2>/dev/null || echo "")

    if [[ -n "$EXISTING" && "$EXISTING" != "null" ]]; then
        log_info "Using existing compartment: $PROJECT_NAME"
        OCI_COMPARTMENT="$EXISTING"
    else
        log_info "Creating compartment: $PROJECT_NAME"
        OCI_COMPARTMENT=$(oci iam compartment create \
            --compartment-id "$OCI_TENANCY" \
            --name "$PROJECT_NAME" \
            --description "GitOps Metal Foundry - Bare Metal Cloud" \
            --wait-for-state ACTIVE \
            --query 'data.id' \
            --raw-output 2>/dev/null) || {
            log_warn "Could not create compartment, using tenancy root"
            OCI_COMPARTMENT="$OCI_TENANCY"
        }
    fi

    log_success "Compartment: ${OCI_COMPARTMENT:0:50}..."
}

#=============================================================================
# Step 7: Get SSH Key
#=============================================================================

get_ssh_key() {
    log_info "SSH public key for VM access"
    echo ""

    SSH_PUBLIC_KEY=""

    # Check for existing keys
    for key_file in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
        if [[ -f "$key_file" ]]; then
            log_info "Found: $key_file"
            read -r -p "Use this key? (Y/n): " use_existing
            if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
                SSH_PUBLIC_KEY=$(cat "$key_file")
                log_success "Using $key_file"
                return
            fi
        fi
    done

    echo "Paste your SSH public key (or press Enter to skip):"
    read -r SSH_PUBLIC_KEY

    if [[ -z "$SSH_PUBLIC_KEY" ]]; then
        log_warn "No SSH key - you won't be able to SSH into VMs"
    fi
}

#=============================================================================
# Step 8: Create and Push terraform.tfvars
#=============================================================================

create_and_push_tfvars() {
    log_info "Creating terraform.tfvars..."

    # Check if we're in the repo directory
    if [[ -d "terraform" ]]; then
        REPO_DIR="."
    else
        # Clone the repo
        REPO_DIR="/tmp/gitops-metal-foundry-$$"
        rm -rf "$REPO_DIR"
        gh repo clone "$GITHUB_OWNER/$GITHUB_REPO" "$REPO_DIR"
    fi

    # Create terraform.tfvars
    cat > "$REPO_DIR/terraform/terraform.tfvars" << EOF
# Generated by bootstrap.sh on $(date)
# OCI Configuration for GitOps Metal Foundry

tenancy_ocid     = "$OCI_TENANCY"
compartment_ocid = "$OCI_COMPARTMENT"
region           = "$OCI_REGION"

# GitHub for OIDC (informational - auth via API key)
github_owner = "$GITHUB_OWNER"
github_repo  = "$GITHUB_REPO"

# SSH public key for VM access
ssh_public_key = "$SSH_PUBLIC_KEY"

# Project name
project_name = "$PROJECT_NAME"
EOF

    log_success "Created terraform/terraform.tfvars"

    # Commit and push
    cd "$REPO_DIR"
    git add terraform/terraform.tfvars

    if git diff --cached --quiet; then
        log_info "No changes to commit"
    else
        git commit -m "feat: add OCI configuration for $OCI_REGION"
        git push origin main
        log_success "Pushed to GitHub"
    fi

    cd - > /dev/null
}

#=============================================================================
# Step 9: Summary
#=============================================================================

print_summary() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  Bootstrap Complete!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}What was configured:${NC}"
    echo ""
    echo "  OCI:"
    echo "    - Compartment: $PROJECT_NAME"
    echo "    - Region: $OCI_REGION"
    echo "    - API Key: ~/.oci/github-actions/oci_api_key.pem"
    echo ""
    echo "  GitHub Secrets (set automatically):"
    echo "    - OCI_CLI_USER"
    echo "    - OCI_CLI_TENANCY"
    echo "    - OCI_CLI_FINGERPRINT"
    echo "    - OCI_CLI_KEY_CONTENT"
    echo "    - OCI_CLI_REGION"
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo ""
    echo "  1. GitHub Actions will run automatically on push"
    echo "     Watch: https://github.com/$GITHUB_OWNER/$GITHUB_REPO/actions"
    echo ""
    echo "  2. Create a PR to trigger terraform plan"
    echo "  3. Merge to main to trigger terraform apply"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Cost: \$0.00/month (Oracle Always Free Tier)${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

#=============================================================================
# Main
#=============================================================================

main() {
    banner
    validate_prerequisites
    get_oci_config
    get_github_repo
    create_api_key
    set_github_secrets
    create_compartment
    get_ssh_key
    create_and_push_tfvars
    print_summary
}

# Handle errors
trap 'log_error "Bootstrap failed at line $LINENO"' ERR

main "$@"
