#!/usr/bin/env bash

set -euo pipefail

STATE_FILE=".app_count_state"
ROOT_DIR="apps"
ROOT_KUST="$ROOT_DIR/kustomization.yaml"
TARGET_NAMESPACE="app-ns"

# 1. Determine Current Existing Count from State File
CURRENT_COUNT=0
if [[ -f "$STATE_FILE" ]]; then
    CURRENT_COUNT=$(cat "$STATE_FILE")
    if ! [[ "$CURRENT_COUNT" =~ ^[0-9]+$ ]]; then
        CURRENT_COUNT=0
    fi
fi

# 2. Gather Interactive User Input
echo "Current application count is: $CURRENT_COUNT"
read -p "Enter the TARGET number of applications to have (e.g., 1500): " TARGET_COUNT
if ! [[ "$TARGET_COUNT" =~ ^[0-9]+$ ]] ; then
   echo "Error: Please enter a valid positive integer." >&2; exit 1
fi

read -p "Enter your Git Repository URL: " REPO_URL
read -p "Enter your Git Target Revision/Branch (default: main): " TARGET_REV
TARGET_REV=${TARGET_REV:-main}

mkdir -p "$ROOT_DIR"

# Target specific semver Alpine web server images
IMAGES=(
  "nginx:1.27.0-alpine"
  "httpd:2.4.53-alpine"
  "caddy:2.8.4-alpine"
)
IMAGES_COUNT=${#IMAGES[@]}

# 3. Always ensure root-app.yaml is present and correct
cat <<EOF > "$ROOT_DIR/root-app.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/manifest-generate-paths: .
  name: root-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    directory:
      recurse: false
    repoURL: $REPO_URL
    targetRevision: $TARGET_REV
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - ApplyOutOfSyncOnly=true
      - Validate=true
      - CreateNamespace=false
      - PrunePropagationPolicy=foreground
      - PruneLast=true
      - SkipDryRunOnMissingResource=true
    retry:
      limit: 3
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 2m
EOF

# Always ensure the root kustomization file template header exists
if [[ ! -f "$ROOT_KUST" ]]; then
cat <<EOF > "$ROOT_KUST"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
EOF
fi

# --------------------------------------------------------
# ACTION LINE: SCALE UP
# --------------------------------------------------------
if (( TARGET_COUNT > CURRENT_COUNT )); then
    echo "Scaling up: Adding missing applications from $CURRENT_COUNT to $((TARGET_COUNT - 1))..."

    for ((i=CURRENT_COUNT; i<TARGET_COUNT; i++)); do
        APP_NAME="app-$i"
        APP_PATH="$ROOT_DIR/$APP_NAME"

        BASE_PATH="$APP_PATH/httpd/base"
        STAGING_PATH="$APP_PATH/httpd/overlays/staging"
        PROD_PATH="$APP_PATH/httpd/overlays/production"
        mkdir -p "$BASE_PATH" "$STAGING_PATH" "$PROD_PATH"

        IMAGE_TO_USE=${IMAGES[$((i % IMAGES_COUNT))]}
        IMAGE_NAME=$(echo "$IMAGE_TO_USE" | cut -d':' -f1)
        IMAGE_TAG=$(echo "$IMAGE_TO_USE" | cut -d':' -f2)

        # A. Append direct folder name to root kustomization
        echo "  - $APP_NAME" >> "$ROOT_KUST"

        # B. Create the app-level application.yaml template pointing to shared 'app-ns'
        cat <<EOF > "$APP_PATH/application.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  annotations:
    argocd.argoproj.io/manifest-generate-paths: .
    argocd.argoproj.io/compare-options: ServerSideDiff=true,IncludeMutationWebhook=true
  name: $APP_NAME
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: $REPO_URL
    targetRevision: $TARGET_REV
    path: apps/$APP_NAME/httpd/overlays/staging
  destination:
    server: https://kubernetes.default.svc
    namespace: $TARGET_NAMESPACE
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - ApplyOutOfSyncOnly=true
      - Validate=true
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
      - SkipDryRunOnMissingResource=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF

        # C. Create top-level app kustomization.yaml
        cat <<EOF > "$APP_PATH/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - application.yaml
EOF

        # D. Build out underlying base manifests
        cat <<EOF > "$BASE_PATH/deployment.yaml"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: web
        image: httpd
        ports:
        - containerPort: 80
EOF

        cat <<EOF > "$BASE_PATH/service.yaml"
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
  labels:
    app: $APP_NAME
spec:
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: $APP_NAME
EOF

        cat <<EOF > "$BASE_PATH/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
EOF

        # E. Build out staging overlay injecting image configurations and resource blocks
        cat <<EOF > "$STAGING_PATH/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: httpd
    newName: $IMAGE_NAME
    newTag: "$IMAGE_TAG"
patches:
  - target:
      kind: Deployment
      name: $APP_NAME
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/resources
        value:
          requests:
            cpu: 50m
            memory: 52Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

        # F. Build out production overlay injecting image configurations and resource blocks
        cat <<EOF > "$PROD_PATH/kustomization.yaml"
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: httpd
    newName: $IMAGE_NAME
    newTag: "$IMAGE_TAG"
patches:
  - target:
      kind: Deployment
      name: $APP_NAME
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/resources
        value:
          requests:
            cpu: 50m
            memory: 52Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF
    done

# --------------------------------------------------------
# ACTION LINE: SCALE DOWN
# --------------------------------------------------------
elif (( TARGET_COUNT < CURRENT_COUNT )); then
    echo "Scaling down: Removing excess applications from $((CURRENT_COUNT - 1)) down to $TARGET_COUNT..."

    for ((i=CURRENT_COUNT-1; i>=TARGET_COUNT; i--)); do
        APP_NAME="app-$i"
        APP_PATH="$ROOT_DIR/$APP_NAME"

        if [[ -d "$APP_PATH" ]]; then
            echo "Removing directory: $APP_PATH"
            rm -rf "$APP_PATH"
        fi

        sed -i.bak "/- ${APP_NAME}$/d" "$ROOT_KUST" && rm -f "${ROOT_KUST}.bak"
    done

else
    echo "No changes required. Target matches current state ($TARGET_COUNT apps)."
fi

# 4. Save Final State Back To State Tracking File
echo "$TARGET_COUNT" > "$STATE_FILE"

echo "--------------------------------------------------------"
echo "Success! All applications are now target-mapped strictly to '$TARGET_NAMESPACE'."
echo "--------------------------------------------------------"