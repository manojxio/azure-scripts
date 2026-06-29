#!/bin/bash

set -euo pipefail

###############################################
# Azure ACR Cleanup Script
#
# Features:
# - Prompts for ACR and repository
# - Deletes images older than N days (default 20)
# - NEVER deletes images tagged "main" or "test"
# - Shows summary before deleting
# - Requires explicit confirmation
###############################################

# Check prerequisites
command -v az >/dev/null 2>&1 || {
    echo "❌ Azure CLI is not installed."
    exit 1
}

command -v jq >/dev/null 2>&1 || {
    echo "❌ jq is not installed."
    exit 1
}

# Verify Azure login
az account show >/dev/null 2>&1 || {
    echo "❌ You are not logged into Azure."
    echo "Run: az login"
    exit 1
}

echo "========================================="
echo " Azure Container Registry Cleanup"
echo "========================================="
echo

# Inputs
read -rp "Enter Azure Container Registry name: " ACR_NAME
[[ -z "$ACR_NAME" ]] && {
    echo "❌ ACR name is required."
    exit 1
}

read -rp "Enter repository name: " REPO_NAME
[[ -z "$REPO_NAME" ]] && {
    echo "❌ Repository name is required."
    exit 1
}

read -rp "Delete images older than how many days? [20]: " DAYS
DAYS=${DAYS:-20}

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "❌ Days must be a positive integer."
    exit 1
fi

# Verify repository exists
if ! az acr repository show \
    --name "$ACR_NAME" \
    --repository "$REPO_NAME" >/dev/null 2>&1; then

    echo
    echo "❌ Repository '$REPO_NAME' does not exist in registry '$ACR_NAME'."
    exit 1
fi

CUTOFF_DATE=$(date -u -d "$DAYS days ago" +"%Y-%m-%dT%H:%M:%SZ")

echo
echo "Scanning repository..."
echo

TOTAL_IMAGES=0
DELETE_COUNT=0
PROTECTED_COUNT=0

declare -a DELETE_LIST

while read -r manifest; do

    [[ -z "$manifest" ]] && continue

    TOTAL_IMAGES=$((TOTAL_IMAGES + 1))

    digest=$(echo "$manifest" | jq -r '.digest')
    updated=$(echo "$manifest" | jq -r '.lastUpdateTime')
    tags=$(echo "$manifest" | jq -r '.tags // [] | join(",")')

    [[ -z "$tags" ]] && tags="<untagged>"

    #
    # Never delete protected tags
    #
    if echo ",$tags," | grep -Eq ',(main|test),'; then
        PROTECTED_COUNT=$((PROTECTED_COUNT + 1))
        continue
    fi

    #
    # Older than cutoff?
    #
    if [[ "$updated" < "$CUTOFF_DATE" ]]; then
        DELETE_COUNT=$((DELETE_COUNT + 1))
        DELETE_LIST+=("$digest|$updated|$tags")
    fi

done < <(
    az acr manifest list-metadata \
        --registry "$ACR_NAME" \
        --name "$REPO_NAME" \
        -o json 2>/dev/null | jq -c '.[]'
)

echo "========================================="
echo "Summary"
echo "========================================="
echo "Registry              : $ACR_NAME"
echo "Repository            : $REPO_NAME"
echo "Retention             : $DAYS days"
echo "Cutoff Date           : $CUTOFF_DATE"
echo
echo "Total Manifests       : $TOTAL_IMAGES"
echo "Protected (main/test) : $PROTECTED_COUNT"
echo "Will be Deleted       : $DELETE_COUNT"
echo "========================================="

if [[ "$DELETE_COUNT" -eq 0 ]]; then
    echo
    echo "Nothing to delete."
    exit 0
fi

echo
echo "The following manifests will be deleted:"
echo

printf "%-70s %-22s %s\n" "DIGEST" "LAST UPDATED" "TAGS"
printf "%-70s %-22s %s\n" "------" "------------" "----"

for item in "${DELETE_LIST[@]}"; do
    IFS="|" read -r digest updated tags <<< "$item"
    printf "%-70s %-22s %s\n" "$digest" "$updated" "$tags"
done

echo
echo "WARNING!"
echo "This action permanently deletes the above manifests."
echo

read -rp "Type 'yes' to continue: " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo
    echo "Operation cancelled."
    exit 0
fi

echo
echo "Deleting manifests..."
echo

DELETED=0

for item in "${DELETE_LIST[@]}"; do

    IFS="|" read -r digest updated tags <<< "$item"

    echo "Deleting: $digest ($tags)"

    az acr repository delete \
        --name "$ACR_NAME" \
        --image "$REPO_NAME@$digest" \
        --yes \
        --only-show-errors

    DELETED=$((DELETED + 1))

done

echo
echo "========================================="
echo "Cleanup Complete"
echo "========================================="
echo "Deleted Manifests : $DELETED"
echo "Protected         : $PROTECTED_COUNT"
echo "Repository        : $REPO_NAME"
echo "========================================="
