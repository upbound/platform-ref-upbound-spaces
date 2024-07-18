oxr = option("params").oxr
_ocds = option("params").ocds
_dxr = option("params").dxr
dcds = option("params").dcds

_defaults = {
    id: oxr.spec.parameters.id or ""
    region: oxr.spec.parameters.region or ""
    deletionPolicy: oxr.spec.parameters.deletionPolicy or "Delete"
    providerConfigName: oxr.spec.providerConfigName or "default"
}

AWSNetwork = {
    apiVersion: "aws.platform.upbound.io/v1alpha1"
    kind: "XNetwork"
    metadata: {
        annotations: {
            "krm.kcl.dev/composition-resource-name" = "network"
        }
    }
    spec: {
        parameters: _defaults
    }
} if oxr.spec.parameters.cloud or "" == "aws" else {}

AWSKubernetes = {
    apiVersion: "aws.platform.upbound.io/v1alpha1"
    kind: "XEKS"
    metadata: {
        annotations: {
            "krm.kcl.dev/composition-resource-name" = "kubernetes"
            "xeks.aws.platform.upbound.io/cluster-id" = oxr.spec.parameters.id or ""
        }
    }
    spec: {
        parameters: _defaults | {
            version: oxr.spec.parameters.version or ""
            nodes: oxr.spec.parameters.nodes or ""
            iam: oxr.spec.parameters.iam or ""
        }
        writeConnectionSecretToRef: {
            name: oxr.metadata.uid and "-eks"
            namespace: oxr.spec.writeConnectionSecretToRef.namespace
        }
    }
} if oxr.spec.parameters.cloud == "aws" else {}

xArgoCd = {
    apiVersion: "gitops.platform.upbound.io/v1alpha1"
    kind: "XArgo"
    metadata: {
        annotations: {
            "krm.kcl.dev/composition-resource-name" = "argocd"
        }
    }
    spec:{
        parameters: {
            deletionPolicy: oxr.spec.parameters.deletionPolicy or "Delete"
            providerConfigName: oxr.spec.parameters.id
            ingressUrl: oxr.spec.parameters.operators.argocd.ingressUrl
            operators: {
                argocd: {
                    version: oxr.spec.parameters.operators.argocd.version or "7.1.1"
                }
            }
            source: {
                git: oxr.spec.parameters.operators.argocd.git
            },
            resourceExclusions: oxr.spec.parameters.operators.argocd.resourceExclusions
            resourceInclusions: oxr.spec.parameters.operators.argocd.resourceInclusions
        },
    }
} if all_true([
    oxr.spec.parameters.operators.argocd.enabled or False
    all_true([
        c.status == "True" for c in _ocds["kubernetes"]?.Resource.status.conditions or False
    ])
]) else {}

usageByArgoCDOfXEKS = {
    apiVersion: "apiextensions.crossplane.io/v1alpha1"
    kind: "Usage"
    metadata: {
        annotations: {
            "krm.kcl.dev/composition-resource-name" = "usage-by-argocd-of-kubernetes"
        }
    }
    spec: {
        by: {
            apiVersion: "gitops.platform.upbound.io/v1alpha1"
            kind: "XArgo"
            resourceSelector: {
                matchControllerRef: True
            },
        },
        of: {
            apiVersion: "aws.platform.upbound.io/v1alpha1"
            kind: "XEKS"
            resourceSelector: {
                matchControllerRef: True
            },
        },
    },
} if all_true([
    oxr.spec.parameters.operators.argocd.enabled or False
    all_true([
        c.status == "True" for c in _ocds["kubernetes"]?.Resource.status.conditions or False
    ])
]) else {}

spacePullSecret = {
    apiVersion: "kubernetes.crossplane.io/v1alpha2"
    kind: "Object"
    metadata: {
        annotations: {
            "krm.kcl.dev/composition-resource-name" = "space-pull-secret"
        }
    }
    spec: {
        references: [
            {
                patchesFrom: {
                    apiVersion: "v1"
                    kind: "Secret"
                    name: "upbound-pull-secret"
                    namespace: "upbound-system"
                    fieldPath: "data[.dockerconfigjson]"
                },
                toFieldPath: "data[.dockerconfigjson]"
            },
        ],
        deletionPolicy: oxr.spec.parameters.deletionPolicy or "Delete"
        forProvider: {
            manifest: {
                "apiVersion": "v1",
                "kind": "Secret",
                "type": "kubernetes.io/dockerconfigjson",
                "metadata": {
                    "name": "upbound-pull-secret",
                    "namespace": "upbound-system",
                },
            },
        },
        providerConfigRef: {
            name: oxr.spec.parameters.providerConfigName or "default"
        },
    },
} if all_true([
    all_true([
        c.status == "True" for c in _ocds["kubernetes"]?.Resource.status.conditions or False
    ])
]) else {}

releaseCertManager = {
    apiVersion: "helm.crossplane.io/v1beta1l"
    kind: "Release"
    metadata: {
        annotations: {
            "crossplane.io/external-name": "cert-manager"
        }
    },
    spec: {
        rollbackLimit: 3,
        deletionPolicy: oxr.spec.parameters.deletionPolicy or "Delete"
        forProvider: {
            namespace: "cert-manager",
            chart: {
                name: "cert-manager",
                version: oxr.spec.parameters.operators.certmanager.version or "v1.14.3"
                repository: "https://charts.jetstack.io"
            },
            values: {
                installCRDs: True,
            },
            waitTimeout: "360s"
        },
        providerConfigRef: {
            name: oxr.spec.parameters.providerConfigName or "default"
        },
    },
} if oxr.spec.parameters.operators.certmanager.enabled or True == True else {}

releaseIngressNginx = {
    apiVersion: "helm.crossplane.io/v1beta1"
    kind: "Release"
    metadata: {
        annotations: {
            "crossplane.io/external-name": "ingress-nginx"
        }
    },
    spec: {
        rollbackLimit: 3,
        deletionPolicy: oxr.spec.parameters.deletionPolicy or "Delete"
        forProvider: {
            namespace: "ingress-nginx"
            chart: {
                name: "ingress-nginx"
                version: oxr.spec.parameters.operators.ingressnginx.version or "4.9.1"
                repository: "https://kubernetes.github.io/ingress-nginx"
            }
            set: [
                {
                    name: "controller.service.type"
                    value: "LoadBalancer"
                },
                {
                    name: "controller.allowSnippetAnnotations",
                    value: "true"
                },
                {
                    name: 'controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"'
                    value: "/healthz"
                },
            ],
        },
        providerConfigRef: {
            name: oxr.spec.parameters.providerConfigName or "default"
        },
    },
} if oxr.spec.parameters.operators.ingressnginx.enabled or True == True else {}

releaseExternalDns = {
    apiVersion: "helm.crossplane.io/v1beta1"
    kind: "Release"
    metadata: {
        annotations: {
            "crossplane.io/external-name": "external-dns"
        }
    },
    spec: {
        rollbackLimit: 3,
        deletionPolicy: oxr.spec.parameters.deletionPolicy or "Delete"
        forProvider: {
            namespace: "external-dns"
            chart: {
                name: "external-dns"
                version: oxr.spec.parameters.operators.externaldns.version or "6.34.2"
                repository: "https://charts.bitnami.com/bitnami"
            },
            values: {
                replicaCount: 1
                domainFilters: [
                    oxr.spec.parameters.operators.externaldns.name
                ],
                serviceAccount: {
                    annotations: [
                        if oxr.spec.parameters.cloud == "aws":
                            {
                                "eks.amazonaws.com/role-arn": oxr.status.status.externalDNS.IRSARoleArn
                            },
                        if oxr.spec.parameters.cloud == "gcp":
                            {
                                "iam.gke.io/gcp-service-account": oxr.status.status.externalDNS.googleServiceAccount.email
                            },
                    ],
                },
                txtOwnerId: "upbound-spaces-" + oxr.metadata.uid
                provider: oxr.spec.parameters.cloud
                policy: "sync"
                source: "ingress"
                registry: "txt"
                if oxr.spec.parameters.cloud == "aws":
                    aws: {
                        batchChangeSize: 4
                        zoneType: "public"
                        region: "us-east-1"
                    },
                if oxr.spec.parameters.cloud == "gcp":
                    google: {
                        project: oxr.spec.parameters.operators.externaldns.gcp.dnsProject
                    }
                rbac: {
                    create: True
                },
                serviceAccount: {
                    create: True
                    name: "external-dns"
                },
                metrics: {
                    enabled: False
                    serviceMonitor: {
                        enabled: False
                    },
                },
                replicas: 2
                podDisruptionBudget: {
                    minAvailable: 1
                },
            },

        },
        providerConfigRef: {
            name: oxr.spec.parameters.providerConfigName or "default"
        },
    }
} if oxr.spec.parameters.operators.externaldns.enabled or True == True else {}

if oxr.spec.parameters.cloud == "aws":
    _identityExternalDNS = {
        apiVersion: "aws.platform.upbound.io/v1alpha1"
        kind: "XIRSA"
        spec: {
            parameters: {
                id: oxr.spec.parameters.providerConfigName or "default"
                condition: "StringEquals"
                serviceAccount: {
                    name: "external-dns"
                    namespace: "external-dns"
                },
                policyDocument: """
                    {
                        "Version":"2012-10-17",
                        "Statement":[
                          {
                            "Effect":"Allow",
                            "Action":[
                              "route53:ListResourceRecordSets",
                              "route53:ListHostedZones"
                            ],
                            "Resource":"*"
                          },
                          {
                            "Effect":"Allow",
                            "Action":"route53:ChangeResourceRecordSets",
                            "Resource":"arn:aws:route53:::hostedzone/${oxr.spec.parameters.operators.externaldns.aws.route53ZoneId}
                          }
                        ]
                    }
                """
            },
        }

    }

if oxr.spec.parameters.cloud == "gcp":
    _identityExternalDNS = {
        apiVersion: "gcp.platform.upbound.io/v1alpha1"
        kind: "XWorkloadIdentity"
        spec: {
          parameters: {
            id: oxr.spec.parameters.providerConfigName
            dnsProject: oxr.spec.parameters.operators.externaldns.gcp.dnsProject
            serviceAccount: {
              name: "external-dns"
              namespace: "external-dns"
            },
          },
        },
    }

releaseSpaces = {
    apiVersion: "helm.crossplane.io/v1beta1"
    kind: "Release"
    metadata: {
        annotations: [
            {
                "crossplane.io/external-name": "spaces"
            },
        ],
    },
    spec: {
        rollbackLimit: 3,
        forProvider: {
            namespace: "upbound-system"
            chart: {
                pullSecretRef: oxr.spec.parameters.spaces.pullSecretRef or {"name": "upbound-provider-helm-pull", "namespace": "upbound-system"}
                version: oxr.spec.parameters.spaces.version or "1.6.0"
                name: "spaces"
                repository: "oci://us-west1-docker.pkg.dev/orchestration-build/upbound-environments"
            },
            set: [
                {
                    name: "account"
                    value: oxr.spec.parameters.spaces.account
                },
                if oxr.spec.parameters.cloud == "gcp":
                    {
                        name: "clusterType"
                        value: "gke"
                    }
                if oxr.spec.parameters.cloud == "aws":
                    {
                        name: "clusterType"
                        value: "eks"
                    }
                if oxr.spec.parameters.cloud == "azure":
                    {
                        name: "clusterType"
                        value: "aks"
                    }
                {
                    name: "ingress.host"
                    value: oxr.spec.parameters.spaces.dns.spacesRouterDomain
                },
                {
                    name: "features.alpha.eso.enabled"
                    value: "true"
                },
                {
                    name: "features.alpha.eso.namespace"
                    value: "external-secrets"
                },
                {
                    name: "features.alpha.argocdPlugin.enabled"
                    value: "true"
                },
                {
                    name: "features.alpha.argocdPlugin.target.secretNamespace"
                    value: "argocd"
                },
            ],
        },
    }
}

items = [i for i in [
    AWSNetwork, AWSKubernetes,
    xArgoCd, usageByArgoCDOfXEKS,
    spacePullSecret,
    # releaseCertManager,
    # releaseIngressNginx,
    # releaseExternalDns, _identityExternalDNS
    # releaseSpaces
] if i]
