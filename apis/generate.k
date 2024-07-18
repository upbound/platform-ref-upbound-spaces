import file
import yaml

_composition = yaml.decode(file.read("apis/template.yaml")) | {
    spec: {
        pipeline = [
            {
                step: "kcl"
                functionRef: {
                    name: "crossplane-contrib-function-kcl"
                }
                input: {
                    apiVersion: "krm.kcl.dev/v1alpha1"
                    kind: "KCLRun"
                    spec: {
                        source = (file.read("apis/main.k"))
                    }
                }
            },
            {
                step: "automatically-detect-ready-composed-resources"
                functionRef: {
                    name: "crossplane-contrib-function-auto-ready"
                },
            },
        ]
    }
}

file.write("apis/composition.yaml", yaml.encode(_composition))
