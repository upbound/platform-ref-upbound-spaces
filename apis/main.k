import regex

oxr = option("params").oxr
_ocds = option("params").ocds
_dxr = option("params").dxr
dcds = option("params").dcds

_metadata = lambda name: str -> any {
    { annotations = { "krm.kcl.dev/composition-resource-name" = name }}
}

get = lambda x: any, y: str, d: any -> any {
    """
    Get an item from a dictionary using a dot separated path.
    If the item is not found, return a default value.
    """
    p = regex.split(y, "\.")
    c = p[0]
    y = ".".join(p[1:])
    x[c] if len(p) == 1 and c in x else d if c not in x else get(x[c], y, d)
}

_defaults = {
    id: get(oxr, "spec.parameters.id", "")
    region: get(oxr, "spec.parameters.region", "")
    deletionPolicy: get(oxr, "spec.parameters.deletionPolicy", "Delete")
    providerConfigName: get(oxr, "spec.providerConfigName", "default")
}

_items = [{
    apiVersion: "aws.platform.upbound.io/v1alpha1"
    kind: "XNetwork"
    metadata: _metadata("network")
    spec.parameters: _defaults
} if get(oxr, "spec.parameters.cloud", "") == "aws" else {} ]

_items += [{
    apiVersion: "aws.platform.upbound.io/v1alpha1"
    kind: "XEKS"
    metadata: _metadata("kubernetes") | {
        annotations: {
            "xeks.aws.platform.upbound.io/cluster-id" = get(oxr, "spec.parameters.id", "")
        }
    }
    spec: {
        parameters: _defaults | {
            version: get(oxr, "spec.parameters.version", "")
            nodes: get(oxr, "spec.parameters.nodes", "")
            iam: get(oxr, "spec.parameters.iam", "")
        }
        writeConnectionSecretToRef: {
            name: get(oxr, "metadata.uid", "") + "-ekscluster"
            namespace: get(oxr, "spec.writeConnectionSecretToRef.namespace", "")
        }
    }
} if get(oxr, "spec.parameters.cloud", "") == "aws" else {} ]

_items += [{
    apiVersion: "gitops.platform.upbound.io/v1alpha1"
    kind: "XArgo"
    metadata: _metadata("argocd")
    spec:{
        parameters: {
            deletionPolicy: get(oxr, "spec.parameters.deletionPolicy", "Delete")
            providerConfigName: get(oxr, "spec.parameters.id", "")
            ingressUrl: get(oxr, "spec.parameters.operators.argocd.ingressUrl", "")
            operators: {
                argocd: {
                    version: get(oxr, "spec.parameters.operators.argocd.version", "7.1.1")
                }
            }
            source: {
                git: get(oxr, "spec.parameters.operators.argocd.git", "")
            },
            resourceExclusions: get(oxr, "spec.parameters.operators.argocd.resourceExclusions", "")
            resourceInclusions: get(oxr, "spec.parameters.operators.argocd.resourceInclusions", "")
        },
    }
} if get(_ocds, "kubernetes.Resource", {}) and get(oxr, "spec.parameters.operators.argocd.enabled", "") and all_true([
    c.status == "True" for c in get(_ocds, "kubernetes.Resource.status.conditions", [])
]) else {} ]

_items += [{
    apiVersion: "apiextensions.crossplane.io/v1alpha1"
    kind: "Usage"
    metadata: _metadata("usage-by-argocd-of-kubernetes")
    spec: {
        by: {
            apiVersion: "gitops.platform.upbound.io/v1alpha1"
            kind: "XArgo"
            resourceSelector: {
                matchControllerRef: True
            },
        },
        of: {

            apiVersion: get(_ocds, "kubernetes.Resource.apiVersion", "")
            kind: get(_ocds, "kubernetes.Resource.kind", "")
            resourceSelector: {
                matchControllerRef: True
            },
        },
    },
} if get(_ocds, "kubernetes.Resource", {}) and get(oxr, "spec.parameters.operators.argocd.enabled", "") and all_true([
    c.status == "True" for c in get(_ocds, "kubernetes.Resource.status.conditions", [])
]) else {} ]

_items += [{
    apiVersion: "kubernetes.crossplane.io/v1alpha2"
    kind: "Object"
    metadata: _metadata("space-pull-secret")
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
        deletionPolicy: get(oxr, "spec.parameters.deletionPolicy", "Delete")
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
        providerConfigRef.name: get(oxr, "spec.parameters.id", "")
    },
} if get(_ocds, "kubernetes.Resource", {}) and all_true([
    c.status == "True" for c in get(_ocds, "kubernetes.Resource.status.conditions", [])
]) else {} ]

_items += [{
    apiVersion: "helm.crossplane.io/v1beta1"
    kind: "Release"
    metadata: _metadata("cert-manager")  | {
        annotations: {
            "crossplane.io/external-name" = "cert-manager"
        }
    }
    spec: {
        rollbackLimit: 3,
        deletionPolicy: get(oxr, "spec.parameters.deletionPolicy", "Delete")
        forProvider: {
            namespace: "cert-manager",
            chart: {
                name: "cert-manager",
                version: get(oxr, "spec.parameters.operators.certmanager.version", "v1.14.3")
                repository: get(oxr, "", "https://charts.jetstack.io")
            },
            values: {
                installCRDs: True,
            },
            waitTimeout: "360s"
        },
        providerConfigRef.name: get(oxr, "spec.parameters.id", "")
    },
} if get(_ocds, "kubernetes.Resource", {}) and all_true([
    c.status == "True" for c in get(_ocds, "kubernetes.Resource.status.conditions", [])
]) else {} ]

_items += [{
    apiVersion: "helm.crossplane.io/v1beta1"
    kind: "Release"
    metadata: _metadata("ingress-nginx")  | {
        annotations: {
            "crossplane.io/external-name" = "ingress-nginx"
        }
    }
    spec: {
        rollbackLimit: 3,
        deletionPolicy: get(oxr, "spec.parameters.deletionPolicy", "Delete")
        forProvider: {
            namespace: "ingress-nginx"
            chart: {
                name: "ingress-nginx"
                version: get(oxr, "spec.parameters.operators.ingressnginx.version", "4.9.1")
                repository: get(oxr, "", "https://kubernetes.github.io/ingress-nginx")
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
                if get(oxr, "spec.parameters.cloud", "") == "aws":
                    {
                        name: 'controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"'
                        value: "/external"
                    },
                    {
                        name: 'controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-scheme"'
                        value: "internet-facing"
                    },
                    {
                        name: 'controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-nlb-target-type"'
                        value: "ip"
                    },
                    {
                        name: 'controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-protocol"'
                        value: "http"
                    },
                    {
                        name: 'controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-path"'
                        value: "/healthz"
                    },
                    {
                        name: 'controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-healthcheck-port"'
                        value: "10254"
                    }
            ],
        },
        providerConfigRef.name: get(oxr, "spec.parameters.id", "")
    },
} if get(_ocds, "kubernetes.Resource", {}) and all_true([
    c.status == "True" for c in get(_ocds, "kubernetes.Resource.status.conditions", [])
]) else {} ]

# releaseExternalDns = {
#     apiVersion: "helm.crossplane.io/v1beta1"
#     kind: "Release"
#     metadata: {
#         annotations: {
#             "crossplane.io/external-name": "external-dns"
#         }
#     },
#     spec: {
#         rollbackLimit: 3,
#         deletionPolicy: oxr.spec.parameters.deletionPolicy or "Delete"
#         forProvider: {
#             namespace: "external-dns"
#             chart: {
#                 name: "external-dns"
#                 version: oxr.spec.parameters.operators.externaldns.version or "6.34.2"
#                 repository: "https://charts.bitnami.com/bitnami"
#             },
#             values: {
#                 replicaCount: 1
#                 domainFilters: [
#                     oxr.spec.parameters.operators.externaldns.name
#                 ],
#                 serviceAccount: {
#                     annotations: [
#                         if oxr.spec.parameters.cloud == "aws":
#                             {
#                                 "eks.amazonaws.com/role-arn": oxr.status.status.externalDNS.IRSARoleArn
#                             },
#                         if oxr.spec.parameters.cloud == "gcp":
#                             {
#                                 "iam.gke.io/gcp-service-account": oxr.status.status.externalDNS.googleServiceAccount.email
#                             },
#                     ],
#                 },
#                 txtOwnerId: "upbound-spaces-" + oxr.metadata.uid
#                 provider: oxr.spec.parameters.cloud
#                 policy: "sync"
#                 source: "ingress"
#                 registry: "txt"
#                 if oxr.spec.parameters.cloud == "aws":
#                     aws: {
#                         batchChangeSize: 4
#                         zoneType: "public"
#                         region: "us-east-1"
#                     },
#                 if oxr.spec.parameters.cloud == "gcp":
#                     google: {
#                         project: oxr.spec.parameters.operators.externaldns.gcp.dnsProject
#                     }
#                 rbac: {
#                     create: True
#                 },
#                 serviceAccount: {
#                     create: True
#                     name: "external-dns"
#                 },
#                 metrics: {
#                     enabled: False
#                     serviceMonitor: {
#                         enabled: False
#                     },
#                 },
#                 replicas: 2
#                 podDisruptionBudget: {
#                     minAvailable: 1
#                 },
#             },

#         },
#         providerConfigRef: {
#             name: oxr.spec.parameters.providerConfigName or "default"
#         },
#     }
# }

# if oxr.spec.parameters.cloud == "aws":
#     _identityExternalDNS = {
#         apiVersion: "aws.platform.upbound.io/v1alpha1"
#         kind: "XIRSA"
#         spec: {
#             parameters: {
#                 id: oxr.spec.parameters.providerConfigName or "default"
#                 condition: "StringEquals"
#                 serviceAccount: {
#                     name: "external-dns"
#                     namespace: "external-dns"
#                 },
#                 policyDocument: """
#                     {
#                         "Version":"2012-10-17",
#                         "Statement":[
#                           {
#                             "Effect":"Allow",
#                             "Action":[
#                               "route53:ListResourceRecordSets",
#                               "route53:ListHostedZones"
#                             ],
#                             "Resource":"*"
#                           },
#                           {
#                             "Effect":"Allow",
#                             "Action":"route53:ChangeResourceRecordSets",
#                             "Resource":"arn:aws:route53:::hostedzone/${oxr.spec.parameters.operators.externaldns.aws.route53ZoneId}
#                           }
#                         ]
#                     }
#                 """
#             },
#         }

#     }

# if oxr.spec.parameters.cloud == "gcp":
#     _identityExternalDNS = {
#         apiVersion: "gcp.platform.upbound.io/v1alpha1"
#         kind: "XWorkloadIdentity"
#         spec: {
#           parameters: {
#             id: oxr.spec.parameters.providerConfigName
#             dnsProject: oxr.spec.parameters.operators.externaldns.gcp.dnsProject
#             serviceAccount: {
#               name: "external-dns"
#               namespace: "external-dns"
#             },
#           },
#         },
#     }

_items += [{
    apiVersion: "helm.crossplane.io/v1beta1"
    kind: "Release"
    metadata: _metadata("spaces")  | {
        annotations: {
            "crossplane.io/external-name" = "spaces"
        }
    }
    spec: {
        rollbackLimit: 3,
        forProvider: {
            namespace: "upbound-system"
            chart: {
                pullSecretRef: get(oxr, "spec.parameters.spaces.pullSecretRef", {"name": "upbound-provider-helm-pull", "namespace": "upbound-system"})
                version: get(oxr, "spec.parameters.spaces.version", "1.6.0")
                name: "spaces"
                repository: get(oxr, "", "oci://us-west1-docker.pkg.dev/orchestration-build/upbound-environments")
            },
            set: [
                {
                    name: "account"
                    value: get(oxr, "spec.parameters.spaces.account", "")
                },
                if get(oxr, "spec.parameters.cloud", "") == "gcp":
                    {
                        name: "clusterType"
                        value: "gke"
                    }
                if get(oxr, "spec.parameters.cloud", "") == "aws":
                    {
                        name: "clusterType"
                        value: "eks"
                    }
                if get(oxr, "spec.parameters.cloud", "") == "azure":
                    {
                        name: "clusterType"
                        value: "aks"
                    }
                {
                    name: "ingress.host"
                    value: get(oxr, "spec.parameters.spaces.dns.spacesRouterDomain", "")
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
        providerConfigRef.name: get(oxr, "spec.parameters.id", "")
    }
} if get(_ocds, "kubernetes.Resource", {}) and all_true([
    c.status == "True" for c in get(_ocds, "kubernetes.Resource.status.conditions", [])
]) else {} ]

# ToDo(haarchri): add more conditions for prereq

items = _items