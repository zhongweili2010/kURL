function openebs_pre_init() {
    if [ -z "$OPENEBS_NAMESPACE" ]; then
        OPENEBS_NAMESPACE=openebs
    fi
    if [ -z "$OPENEBS_LOCALPV_STORAGE_CLASS" ]; then
        OPENEBS_LOCALPV_STORAGE_CLASS=openebs-localpv
    fi

    export OPENEBS_APP_VERSION="3.2.0"
    export PREVIOUS_OPENEBS_VERSION="$(openebs_get_running_version)"

    openebs_bail_unsupported_upgrade
}

function openebs() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION"
    local dst="$DIR/kustomize/openebs"

    secure_openebs

    openebs_apply_crds

    # migrate resources that are changing names
    openebs_migrate_pre_helm_resources

    openebs_apply_operator

    # migrate resources that are changing names
    openebs_migrate_post_helm_resources

    openebs_apply_storageclasses
}

function openebs_apply_crds() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/crds"
    local dst="$DIR/kustomize/openebs/spec/crds"

    mkdir -p "$dst"

    cp "$src/kustomization.yaml" "$dst/"
    cp "$src/crds.yaml" "$dst/"

    kubectl apply -k "$dst/"
}

function openebs_apply_operator() {
    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec"
    local dst="$DIR/kustomize/openebs/spec"

    mkdir -p "$dst"

    render_yaml_file_2 "$src/tmpl-kustomization.yaml" > "$dst/kustomization.yaml"
    render_yaml_file_2 "$src/tmpl-namespace.yaml" > "$dst/namespace.yaml"
    cat "$src/openebs.tmpl.yaml" | sed "s/__OPENEBS_NAMESPACE__/$OPENEBS_NAMESPACE/" > "$dst/openebs.yaml"

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        openebs_iscsi

        kubectl apply -k "$dst/"
        openebs_cspc_upgrade # upgrade the CSPC pools

        cat "$src/cstor.tmpl.yaml" | sed "s/__OPENEBS_NAMESPACE__/$OPENEBS_NAMESPACE/" > "$dst/cstor.yaml"
        insert_resources "$dst/kustomization.yaml" cstor.yaml
    fi

    kubectl apply -k "$dst/"

    logStep "Waiting for OpenEBS operator to apply CustomResourceDefinitions"
    spinner_until 120 kubernetes_resource_exists default crd blockdevices.openebs.io

    openebs_cleanup_kubesystem
    logSuccess "OpenEBS CustomResourceDefinitions are ready"
}

function openebs_apply_storageclasses() {
    # allow vendor to add custom storageclasses rather than the ones built into add-on
    if [ "$OPENEBS_CSTOR" != "1" ] && [ "$OPENEBS_LOCALPV" != "1" ]; then
        return
    fi

    local src="$DIR/addons/openebs/$OPENEBS_VERSION/spec/storage"
    local dst="$DIR/kustomize/openebs/spec/storage"

    mkdir -p "$dst"

    cp "$src/kustomization.yaml" "$dst/"

    if [ "$OPENEBS_CSTOR" = "1" ]; then
        report_addon_start "openebs-cstor" "$OPENEBS_APP_VERSION"

        bail "cstor is not yet supported on OpenEBS $OPENEBS_APP_VERSION."

        report_addon_success "openebs-cstor" "$OPENEBS_APP_VERSION"
    fi

    if [ "$OPENEBS_LOCALPV" = "1" ]; then
        report_addon_start "openebs-localpv" "$OPENEBS_APP_VERSION"

        render_yaml_file_2 "$src/tmpl-localpv-storage-class.yaml" > "$dst/localpv-storage-class.yaml"
        insert_resources "$dst/kustomization.yaml" localpv-storage-class.yaml

        if [ "$OPENEBS_LOCALPV_STORAGE_CLASS" = "default" ]; then
            render_yaml_file_2 "$src/tmpl-patch-localpv-default.yaml" > "$dst/patch-localpv-default.yaml"
            insert_patches_strategic_merge "$dst/kustomization.yaml" patch-localpv-default.yaml
        fi

        report_addon_success "openebs-localpv" "$OPENEBS_APP_VERSION"
    fi

    kubectl apply -k "$dst/"
}

function openebs_join() {
    secure_openebs
}

function openebs_get_running_version() {
    if kubectl get ns "$OPENEBS_NAMESPACE" >/dev/null 2>&1 ; then
        kubectl -n "$OPENEBS_NAMESPACE" get deploy openebs-provisioner -o jsonpath='{.metadata.labels.openebs\.io/version}' 2>/dev/null
    fi
}

function openebs_bail_unsupported_upgrade() {
    if [ -z "$PREVIOUS_OPENEBS_VERSION" ]; then
        return 0
    fi

    semverCompare "$PREVIOUS_OPENEBS_VERSION" "2.0.0"
    if [ "$SEMVER_COMPARE_RESULT" = "-1" ]; then
        logFail "Upgrades from versions prior to 2.x of OpenEBS are unsupported."
        bail "Please first upgrade to 2.6.0."
    fi
}

function secure_openebs() {
    mkdir -p /var/openebs
    chmod 700 /var/openebs
}

function openebs_cleanup_kubesystem() {
    # cleanup old kube-system statefulsets
    # https://github.com/openebs/upgrade/blob/v2.12.2/docs/upgrade.md#prerequisites-1
    kubectl -n kube-system delete sts openebs-cstor-csi-controller 2>/dev/null || true
    kubectl -n kube-system delete ds openebs-cstor-csi-node 2>/dev/null || true
    kubectl -n kube-system delete sa openebs-cstor-csi-controller-sa,openebs-cstor-csi-node-sa 2>/dev/null || true
}

function openebs_migrate_pre_helm_resources() {
    # name changed from maya-apiserver-service > openebs-apiservice
    kubectl -n "$OPENEBS_NAMESPACE" delete service maya-apiserver-service 2>/dev/null || true
    # name changed from cvc-operator-service > openebs-cstor-cvc-operator-svc
    kubectl -n "$OPENEBS_NAMESPACE" delete service cvc-operator-service 2>/dev/null || true
    # name changed from maya-apiserver >openebs-apiserver
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment maya-apiserver 2>/dev/null || true
    # name changed from cspc-operator > openebs-cstor-cspc-operator
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment cspc-operator 2>/dev/null || true
    # name changed from cvc-operator > openebs-cstor-cvc-operator
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment cvc-operator 2>/dev/null || true

    # the selectors for these resources changed
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-localpv-provisioner 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-ndm-operator 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete daemonset openebs-ndm 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-provisioner 2>/dev/null || true
    kubectl -n "$OPENEBS_NAMESPACE" delete deployment openebs-snapshot-operator 2>/dev/null || true
}

function openebs_migrate_post_helm_resources() {
    # name changed from openebs-maya-operator > openebs
    kubectl delete serviceaccount openebs-maya-operator 2>/dev/null || true
    # name changed from openebs-maya-operator > openebs
    kubectl delete clusterrole openebs-maya-operator 2>/dev/null || true
    # name changed from openebs-maya-operator > openebs
    kubectl delete clusterrolebinding openebs-maya-operator 2>/dev/null || true
}
