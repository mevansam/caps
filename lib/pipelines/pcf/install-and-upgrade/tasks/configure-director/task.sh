#!/bin/bash

source automation/lib/scripts/utility/template-utils.sh

[[ -n "$TRACE" ]] && set -x
set -eo pipefail

# Source terraform output variables if available
source_variables 'terraform-output/pcf-env-*.sh'

# Retrieve configured AZs if any which will be passed 
# as a json arg to the az_configuration template as their 
# GUIDs need to be cross-referenced by the template.
CURR_AZ_CONFIGURATION=$(om \
  --skip-ssl-validation \
  --target "https://${OPSMAN_HOST}" \
  --client-id "${OPSMAN_CLIENT_ID}" \
  --client-secret "${OPSMAN_CLIENT_SECRET}" \
  --username "${OPSMAN_USERNAME}" \
  --password "${OPSMAN_PASSWORD}" \
  curl --silent --path /api/v0/staged/director/availability_zones | jq .availability_zones)

# Retrieve configured networks if any which will be  
# passed as a json arg to the network_configuration  
# template as their GUIDs need to be cross-referenced 
# by the template.
CURR_NETWORK_CONFIGURATION=$(om \
  --skip-ssl-validation \
  --target "https://${OPSMAN_HOST}" \
  --client-id "${OPSMAN_CLIENT_ID}" \
  --client-secret "${OPSMAN_CLIENT_SECRET}" \
  --username "${OPSMAN_USERNAME}" \
  --password "${OPSMAN_PASSWORD}" \
  curl --silent --path /api/v0/staged/director/networks)

OPSMAN_CA_CERT=$(om \
  --skip-ssl-validation \
  --target "https://${OPSMAN_HOST}" \
  --client-id "${OPSMAN_CLIENT_ID}" \
  --client-secret "${OPSMAN_CLIENT_SECRET}" \
  --username "${OPSMAN_USERNAME}" \
  --password "${OPSMAN_PASSWORD}" \
  certificate-authorities \
  --format json \
  | jq -r '.[] | select(.issuer | match("Pivotal")) | .cert_pem')

export CA_CERTS=$(echo -e "${OPSMAN_CA_CERT}\n${CA_CERTS}")

iaas_configuration=$(eval_jq_templates "iaas_configuration" "$TEMPLATE_PATH" "$TEMPLATE_OVERRIDE_PATH" "$IAAS")
director_configuration=$(eval_jq_templates "director_configuration" "$TEMPLATE_PATH" "$TEMPLATE_OVERRIDE_PATH" "$IAAS")
az_configuration=$(eval_jq_templates "az_configuration" "$TEMPLATE_PATH" "$TEMPLATE_OVERRIDE_PATH" "$IAAS")
networks_configuration=$(eval_jq_templates "network_configuration" "$TEMPLATE_PATH" "$TEMPLATE_OVERRIDE_PATH" "$IAAS")
network_assignment=$(eval_jq_templates "network_assignment" "$TEMPLATE_PATH" "$TEMPLATE_OVERRIDE_PATH" "$IAAS")
security_configuration=$(eval_jq_templates "security_configuration" "$TEMPLATE_PATH" "$TEMPLATE_OVERRIDE_PATH" "$IAAS")
resource_configuration=$(eval_jq_templates "resource_configuration" "$TEMPLATE_PATH" "$TEMPLATE_OVERRIDE_PATH" "$IAAS")

if [[ "$TRACE" == "render-templates-only" ]]; then

  set +x

  echo -e "\n**** IAAS Configuration ****\n$iaas_configuration"
  echo -e "\n**** Director Configuration ****\n$director_configuration"
  echo -e "\n**** Availability Zones Configuration ****\n$az_configuration"
  echo -e "\n**** Networks Configuration ****\n$networks_configuration"
  echo -e "\n**** Network Assignment Configuration ****\n$network_assignment"
  echo -e "\n**** Security Configuration ****\n$security_configuration"
  echo -e "\n**** Resource Configuration ****\n$resource_configuration"

else
  data=$(jq -n \
    --argjson iaas_configuration "$iaas_configuration" \
    --argjson director_configuration "$director_configuration" \
    --argjson az_configuration "$az_configuration" \
    --argjson networks_configuration "$networks_configuration" \
    --argjson security_configuration "$security_configuration" \
    --argjson resource_configuration "$resource_configuration" \
    '{
      "iaas_configuration": $iaas_configuration,
      "director_configuration": $director_configuration,
      "az_configuration": $az_configuration,
      "networks_configuration": $networks_configuration,
      "security_configuration": $security_configuration,
      "resource_configuration": $resource_configuration
    }')

  om \
    --skip-ssl-validation \
    --target "https://${OPSMAN_HOST}" \
    --client-id "${OPSMAN_CLIENT_ID}" \
    --client-secret "${OPSMAN_CLIENT_SECRET}" \
    --username "${OPSMAN_USERNAME}" \
    --password "${OPSMAN_PASSWORD}" \
    curl \
    --silent --path /api/v0/staged/director/properties \
    --request PUT --data "$data"

  set +e

  # This will fail if network assignment has already been 
  # done. If it fails simply show a warning and continue.
  
  data=$(jq -n \
    --argjson network_assignment "$network_assignment" \
    '{
      "network_and_az": $network_assignment
    }')

  om \
    --skip-ssl-validation \
    --target "https://${OPSMAN_HOST}" \
    --client-id "${OPSMAN_CLIENT_ID}" \
    --client-secret "${OPSMAN_CLIENT_SECRET}" \
    --username "${OPSMAN_USERNAME}" \
    --password "${OPSMAN_PASSWORD}" \
    curl \
    --silent --path /api/v0/staged/director/network_and_az \
    --request PUT --data "$data"

  if [[ $? -ne 0 ]]; then
    echo "WARNING! Network assignment failed. Most likely this has already been done and cannot be changed once applied."
  fi
fi
