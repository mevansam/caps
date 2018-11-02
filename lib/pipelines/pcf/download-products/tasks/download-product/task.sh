#!/bin/bash

[[ -n "$TRACE" ]] && set -x
set -eu

TILE_FILE_PATH=`find ./pivnet-product -name *.pivotal | sort | head -1`

STEMCELL_VERSION=$(
  cat ./pivnet-product/metadata.json |
  jq --raw-output \
    '
    [
      .Dependencies[]
      | select(.Release.Product.Name | contains("Stemcells"))
      | .Release.Version
    ]
    | map(split(".") | map(tonumber))
    | transpose | transpose
    | max // empty
    | map(tostring)
    | join(".")
    '
)

if [ -n "$STEMCELL_VERSION" ]; then

  set +e
  diagnostic_report=$(
    om \
      --target https://$OPSMAN_HOST \
      --client-id "${OPSMAN_CLIENT_ID}" \
      --client-secret "${OPSMAN_CLIENT_SECRET}" \
      --username "$OPSMAN_USERNAME" \
      --password "$OPSMAN_PASSWORD" \
      --skip-ssl-validation \
      curl --silent --path "/api/v0/diagnostic_report"
  )
  if [[ $? -eq 0 ]]; then
    stemcell=$(
      echo $diagnostic_report |
      jq \
        --arg version "$STEMCELL_VERSION" \
        --arg glob "$IAAS" \
      '.stemcells[] | select(contains($version) and contains($glob))'
    )
  else
    stemcell=""
  fi
  set -e

  if [[ -z "$stemcell" ]]; then
    echo "Downloading stemcell $STEMCELL_VERSION"
    cd ./pivnet-product

    product_slug=$(
      jq --raw-output \
        '
        if any(.Dependencies[]; select(.Release.Product.Name | contains("Stemcells for PCF (Windows)"))) then
          "stemcells-windows-server"
        else
          "stemcells"
        end
        ' < ./metadata.json
    )

    pivnet-cli login --api-token="$PIVNET_API_TOKEN"
    
    set +e
    pivnet-cli download-product-files -p "$product_slug" -r $STEMCELL_VERSION -g "*${IAAS}*" --accept-eula
    if [[ $? -ne 0 ]]; then
      set -e

      # Download stemcell from bosh.io
      case "$IAAS" in
        google)
          stemcell_download_url=https://s3.amazonaws.com/bosh-gce-light-stemcells/light-bosh-stemcell-${STEMCELL_VERSION}-google-kvm-ubuntu-xenial-go_agent.tgz
          ;;
        # aws)
        #   ;;
        # azure)
        #   ;;
        # vsphere)
        #   ;;
        # openstack)
        #   ;;
        *)
          echo "ERROR! Unknown IAAS - $IAAS."
          exit 1
          ;;
      esac

      curl -OL $stemcell_download_url
    else
      set -e
    fi

    if [ ! -f "$(find ./ -name *.tgz)" ]; then
      echo "Stemcell file not found!"
      exit 1
    fi
    cd -
  fi
fi

tar cvzf pivnet-product.tgz ./pivnet-product

#
# Upload product metadata, tile and stemcell to local s3 repo
#
mc config host add auto ${AUTOS3_URL} ${AUTOS3_ACCESS_KEY} ${AUTOS3_SECRET_KEY}

NAME=$(echo "${TILE_FILE_PATH##*/}" | sed "s|\(.*\)-[0-9]*\.[0-9]*\.[0-9]*.*|\1|")
VERSION=$(cat ./pivnet-product/metadata.json | jq --raw-output '.Release.Version')

PRODUCT_NAME=${NAME}_${VERSION}

# Keep only the 3 most recent versions
PRODUCT_VERSIONS=$(mc ls --recursive auto/${BUCKET}/downloads \
  | sort \
  | awk "/ ${NAME}_/{ print \$5 }" \
  | cut -d '.' -f 1 \
  | uniq)

NUM_VERSIONS=$(echo "${PRODUCT_VERSIONS}" | wc -l)
if [[ ${NUM_VERSIONS} -gt 3 ]]; then
  for v in $(echo "${PRODUCT_VERSIONS}" | head -$((${NUM_VERSIONS}-3))); do
    echo mc rm auto/${BUCKET}/downloads/${v}.tgz
  done
fi

# Upload new files
mc cp ./pivnet-product.tgz auto/${BUCKET}/downloads/${PRODUCT_NAME}.tgz
