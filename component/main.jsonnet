// main template for metallb
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.metallb;

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: {
      app: 'metallb',
      'app.kubernetes.io/name': 'metallb',
      'app.kubernetes.io/instance': 'metallb',
    }
  },
};

local memberlist_secret = kube.Secret(params.speaker.secretname) {
  metadata+: {
    namespace: params.namespace,
  },
  // need to use stringData here for secret reveal to work
  stringData+: {
    secretkey: params.memberlist_secretkey,
  },
};

local configmap = kube.ConfigMap(params.configmap_name) {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    config: std.manifestYamlDoc(if params.config == null then {
      "address-pools": [
        {
          "name": "default",
          "protocol": "layer2",
          "addresses": params.addresses,
        },
      ],
    } else params.config),
  },
};

// Define outputs below
{
  '00_namespace': namespace,
  [if params.memberlist_secretkey != "" then '01_memberlist_secret']: memberlist_secret,
  '02_configmap': configmap,
}
