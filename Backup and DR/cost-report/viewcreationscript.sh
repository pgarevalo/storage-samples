#!/bin/bash

#Copyright 2025 Google LLC

#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at

#    https://www.apache.org/licenses/LICENSE-2.0

#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.

set -e
# set -x # Uncomment for detailed debugging

# --- Configuration File ---
CONFIG_FILE=${CONFIG_FILE:-"config.json"}

# --- Check for jq and install if not found ---
if ! command -v jq &> /dev/null; then
    echo "INFO: jq command not found. This script requires jq to parse config.json."
    if command -v apt-get &> /dev/null; then
        echo "Attempting to install jq using apt-get..."
        sudo apt-get update
        sudo apt-get install -y jq
    elif command -v dnf &> /dev/null; then
        echo "Attempting to install jq using dnf..."
        sudo dnf install -y jq
    elif command -v yum &> /dev/null; then
        echo "Attempting to install jq using yum..."
        sudo yum install -y jq
    else
        echo "ERROR: Package managers (apt-get, dnf, yum) not found. Cannot automatically install jq."
        echo "Please install jq manually for your system and re-run the script."
        exit 1
    fi

    # Verify installation
    if ! command -v jq &> /dev/null; then
        echo "ERROR: jq installation failed. Please try installing jq manually."
        exit 1
    else
        echo "INFO: jq installed successfully."
    fi
fi

# --- Hardcoded Configuration ---
# Values previously in config.json that are needed by this script
TARGET_DATASET_ID=${TARGET_DATASET_ID:-"BackupDr_Billing_Reports"} # Used in create_looker_studio_view
DTS_TARGET_TABLE_PREFIX=${DTS_TARGET_TABLE_PREFIX:-"BackupDr_Billing_Report"} # Used in create_looker_studio_view

# --- Helper functions to read from JSON ---
json_get() {
    local filter=$1
    jq -r "${filter}" "$CONFIG_FILE"
}

# Function to read a JSON array into a bash array
json_get_array() {
    local filter=$1
    local -a values=()
    readarray -t values < <(jq -r "${filter}[]" "$CONFIG_FILE" 2>/dev/null)
    echo "${values[@]}"
}

# --- Helper function to generate ENV_SUFFIX for a single project ---
generate_env_suffix() {
  local project_id=$1
  local suffix
  # Sanitize and truncate the project ID to create a valid suffix.
  suffix=$(echo "${project_id}" | sed "s/[^a-zA-Z0-9_-]/_/g")
  suffix=${suffix:0:30}
  suffix=$(echo "${suffix}" | sed 's/_$//')
  echo "${suffix}"
}

# --- Function to get the SELECT clause for the view ---
_get_view_select_clause() {
cat <<'EOF'
report_date, resource_name, resource_type, billing_location,
        CASE
          WHEN sku_description LIKE '%Long-Term Retention%' THEN 'Backup Management - LTR'
          WHEN sku_description LIKE '%BackupDR: Storage%' THEN 'Backup Vault Storage'
          WHEN sku_description LIKE '%BackupDR: Management%' THEN 'Backup Management'
          ELSE sku_description
        END AS cost_type,
        usage_in_pricing_units, usage_pricing_unit, net_cost, currency, backup_vault_name, resource_location,
        backup_plan_name, backup_vault_location, source_project
EOF
}

# --- Function to get the full view query string ---
# If table_pattern contains '*', it assumes querying dated tables and adds a WHERE clause.
# Otherwise, it assumes querying a single table (for testing).
_get_looker_studio_view_query() {
  local project_id="$1"
  local dataset_id="$2"
  local table_pattern="$3"
  local from_date_suffix="$4"
  local select_clause
  select_clause=$(_get_view_select_clause)

  echo "SELECT ${select_clause} FROM \`${project_id}.${dataset_id}.${table_pattern}\` WHERE _TABLE_SUFFIX BETWEEN '${from_date_suffix}' AND FORMAT_DATE('%Y%m%d', CURRENT_DATE())"
}

# --- Function to create or replace the Looker Studio view ---
create_looker_studio_view() {
  local rpt_project_id="$1"
  local env_suffix="$2"
  local rpt_dataset="${TARGET_DATASET_ID}"

  local bq_safe_env_suffix
  bq_safe_env_suffix=$(echo "${env_suffix}" | tr '-' '_')
  local rpt_view_name="BackupDr_Billing_Report"
  local rpt_table_pattern="${DTS_TARGET_TABLE_PREFIX}_*"
  local rpt_view_from_date_suffix="20000101"

  # Convert project name to be BQ CLI compatible (dashes instead of underscores)
  local bq_project_id=${rpt_project_id//_/-}

  echo "  Target Project ID: ${bq_project_id}"
  echo "  Target Dataset ID: ${rpt_dataset}"
  echo "  View Name: ${rpt_view_name}"
  echo "  Table Pattern: ${rpt_table_pattern}"

  if ! bq --project_id "${bq_project_id}" show "${rpt_dataset}" > /dev/null 2>&1; then
    echo "  ERROR: Dataset ${rpt_dataset} does not exist in project ${bq_project_id}."
    return 1
  fi

  echo "  Creating or replacing view ${rpt_view_name} in ${bq_project_id}:${rpt_dataset}..."
  local view_query
  view_query=$(_get_looker_studio_view_query "${bq_project_id}" "${rpt_dataset}" "${rpt_table_pattern}" "${rpt_view_from_date_suffix}")
  local ddl_query="CREATE OR REPLACE VIEW \`${bq_project_id}.${rpt_dataset}.${rpt_view_name}\` AS ${view_query}"

  if echo "${ddl_query}" | bq query --use_legacy_sql=false --project_id="${bq_project_id}"; then
    echo "  View ${rpt_view_name} created/replaced successfully."
  else
    echo "  ERROR: Failed to create or replace view ${rpt_view_name}."; return 1
  fi
  return 0
}

# ------------------------------------------------------------------------------
# SECTION - MAIN EXECUTION
# ------------------------------------------------------------------------------
run_main() {
COST_REPORT_VERSION="0.1"
echo "BackupDR Cost Report View Creation Script Version: ${COST_REPORT_VERSION}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: Configuration file not found: $CONFIG_FILE"
  exit 1
fi

# --- Load Configuration from JSON ---
VAULT_PROJECTS_LIST=($(json_get_array '.vault_projects'))
TARGET_PROJECT_ID_VIEW=$(json_get '.target_project_id')
[ "$TARGET_PROJECT_ID_VIEW" == "null" ] && TARGET_PROJECT_ID_VIEW=""

echo "--- Starting Looker Studio View Creation Process ---"

if [[ -n "${TARGET_PROJECT_ID_VIEW}" ]]; then
  echo "--- DEPLOYMENT MODE: Centralized View in a Dedicated Project ---"
  project="${TARGET_PROJECT_ID_VIEW}"
  echo ""
  echo "********************************************************************************"
  echo " Processing for TARGET_PROJECT_ID: ${project} "
  echo "********************************************************************************"

  CURRENT_ENV_SUFFIX=$(generate_env_suffix "${project}")
  echo "  Generated ENV_SUFFIX: ${CURRENT_ENV_SUFFIX}"

  create_looker_studio_view "${project}" "${CURRENT_ENV_SUFFIX}"
  if [[ $? -ne 0 ]]; then
    echo "  ERROR: View creation failed for project ${project}."
    return 1
  else
    echo "  SUCCESS: View creation task finished for project ${project}."
  fi
  echo "********************************************************************************"
  echo ""
else
  echo "--- DEPLOYMENT MODE: Isolated Data Sets in Vault Projects ---"
  if [[ ${#VAULT_PROJECTS_LIST[@]} -eq 0 ]]; then
    echo "ERROR: vault_projects is empty in $CONFIG_FILE, and no target_project_id provided."
    exit 1
  fi

  for project in "${VAULT_PROJECTS_LIST[@]}"; do
    project=$(echo "${project}" | xargs)
    if [[ -z "${project}" ]]; then continue; fi

    echo ""
    echo "********************************************************************************"
    echo " Processing for TARGET_PROJECT_ID: ${project} "
    echo "********************************************************************************"

    CURRENT_ENV_SUFFIX=$(generate_env_suffix "${project}")
    echo "  Generated ENV_SUFFIX: ${CURRENT_ENV_SUFFIX}"

    create_looker_studio_view "${project}" "${CURRENT_ENV_SUFFIX}"
    if [[ $? -ne 0 ]]; then
      echo "  ERROR: View creation failed for project ${project}."
    else
      echo "  SUCCESS: View creation task finished for project ${project}."
    fi
    echo "********************************************************************************"
    echo ""
  done
fi

echo "All view tasks completed."
}

# If script is run directly, execute run_main.
# If sourced, only helper functions above are defined.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_main
fi