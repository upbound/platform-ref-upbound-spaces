#!/usr/bin/env bash
set -aeuo pipefail

UPTEST_GCP_PROJECT=${UPTEST_GCP_PROJECT:-official-provider-testing}

echo "Running setup.sh"
echo "Waiting until all configuration packages are healthy/installed..."
"${KUBECTL}" wait configuration.pkg --all --for=condition=Healthy --timeout 10m
"${KUBECTL}" wait configuration.pkg --all --for=condition=Installed --timeout 10m
"${KUBECTL}" wait configurationrevisions.pkg --all --for=condition=Healthy --timeout 10m

echo "Waiting until all installed provider packages are healthy..."
"${KUBECTL}" wait provider.pkg --all --for condition=Healthy --timeout 10m

echo "Waiting for all pods to come online..."
"${KUBECTL}" -n upbound-system wait --for=condition=Available deployment --all --timeout=5m

echo "Waiting for all XRDs to be established..."
"${KUBECTL}" wait xrd --all --for condition=Established

if [[ -n "${UPTEST_CLOUD_CREDENTIALS:-}" ]]; then
  eval "${UPTEST_CLOUD_CREDENTIALS}"

  if [[ -n "${AWS:-}" ]]; then
    echo "Creating the AWS default cloud credentials secret..."
    ${KUBECTL} -n upbound-system create secret generic aws-creds --from-literal=credentials="${AWS}" --dry-run=client -o yaml | ${KUBECTL} apply -f -

    echo "Creating the AWS default provider config..."
    cat <<EOF | ${KUBECTL} apply -f -
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      name: aws-creds
      namespace: upbound-system
      key: credentials
EOF
  fi

  if [[ -n "${GCP:-}" ]]; then
    echo "Creating the GCP default cloud credentials secret..."
    ${KUBECTL} -n upbound-system create secret generic gcp-creds --from-literal=credentials="${GCP}" --dry-run=client -o yaml | ${KUBECTL} apply -f -

    echo "Creating the GCP default provider config..."
    cat <<EOF | ${KUBECTL} apply -f -
apiVersion: gcp.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    secretRef:
      key: credentials
      name: gcp-creds
      namespace: upbound-system
    source: Secret
  projectID: ${UPTEST_GCP_PROJECT}
EOF
  fi

  if [[ -n "${SPACES:-}" ]]; then
    echo "Creating the SPACES pull secrets..."

    ${KUBECTL} -n upbound-system create secret generic upbound-provider-helm-pull \
      --from-literal=username="_json_key" \
      --from-literal=password="${SPACES}"

    ${KUBECTL} -n upbound-system create secret docker-registry upbound-pull-secret \
      --docker-server="https://us-west1-docker.pkg.dev" \
      --docker-username="_json_key" \
      --docker-password="${SPACES}" \
      --docker-email="uptest@upbound.io"
  fi

  if [[ -n "${AZURE:-}" ]]; then
    echo "Creating the AZURE default cloud credentials secret..."
    ${KUBECTL} -n upbound-system create secret generic azure-creds --from-literal=credentials="${AZURE}" --dry-run=client -o yaml | ${KUBECTL} apply -f -

    echo "Creating the Azure default provider config..."
    cat <<EOF | ${KUBECTL} apply -f -
apiVersion: azure.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default
spec:
  credentials:
    source: Secret
    secretRef:
      name: azure-creds
      namespace: upbound-system
      key: credentials
EOF
  fi
fi
