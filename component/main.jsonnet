// main template for metallb
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.metallb;

local labels = {
  app: 'metallb',
};

local default_metadata(obj) =
  obj {
    metadata+: {
      namespace: params.namespace,
      labels: labels,
    },
  };

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels: labels,
  },
};

// Secret + ConfigMap
local secretkey = default_metadata(kube.Secret('memberlist')) {
  data: {
    secretkey: std.base64(params.secretkey),
  },
};

local config = {
  'address-pools': [{
    name: 'default',
    protocol: params.protocol,
    addresses: params.addresses,
  }],
};

local configmap = default_metadata(kube.ConfigMap('config')) {
  data: {
    config: kap.yaml_dump(config),
  },
};

// Service Accounts
local controller_serviceaccount = default_metadata(kube.ServiceAccount('controller'));
local speaker_serviceaccount = default_metadata(kube.ServiceAccount('speaker'));

// Cluster Roles
local controller_clusterrole = default_metadata(kube.ClusterRole(params.namespace + ':controller') {
  rules: [{
    apiGroups: [''],
    resources: ['services'],
    verbs: ['get', 'list', 'watch', 'update'],
  }, {
    apiGroups: [''],
    resources: ['services/status'],
    verbs: ['update'],
  }, {
    apiGroups: [''],
    resources: ['events'],
    verbs: ['create', 'patch'],
  }, {
    apiGroups: ['policy'],
    resources: ['podsecuritypolicies'],
    verbs: ['use'],
    resourceNames: ['controller'],
  }],
});

local speaker_clusterrole = default_metadata(kube.ClusterRole(params.namespace + ':speaker') {
  rules: [{
    apiGroups: [''],
    resources: ['services', 'endpoints', 'nodes'],
    verbs: ['get', 'list', 'watch'],
  }, {
    apiGroups: [''],
    resources: ['events'],
    verbs: ['create', 'patch'],
  }, {
    apiGroups: ['policy'],
    resources: ['podsecuritypolicies'],
    verbs: ['use'],
    resourceNames: ['speaker'],
  }],
});

// Cluster Role Bindings
local controller_clusterrolebinding = default_metadata(kube.ClusterRoleBinding(controller_clusterrole.metadata.name) {
  subjects_: [controller_serviceaccount],
  roleRef_: controller_clusterrole,
});
local speaker_clusterrolebinding = default_metadata(kube.ClusterRoleBinding(speaker_clusterrole.metadata.name) {
  subjects_: [speaker_serviceaccount],
  roleRef_: speaker_clusterrole,
});

// Roles
local role_config_watcher = default_metadata(kube.Role('config-watcher') {
  rules: [{
    apiGroups: [''],
    resources: ['configmaps'],
    verbs: ['get', 'list', 'watch'],
  }],
});

local role_pod_lister = default_metadata(kube.Role('pod-lister') {
  rules: [{
    apiGroups: [''],
    resources: ['pods'],
    verbs: ['list'],
  }],
});

// Role Bindings
local rolebinding_config_watcher = default_metadata(kube.RoleBinding('config-watcher') {
  subjects_: [controller_serviceaccount, speaker_serviceaccount],
  roleRef_: role_config_watcher,
});

local rolebinding_pod_lister = default_metadata(kube.RoleBinding('pod-lister') {
  subjects_: [speaker_serviceaccount],
  roleRef_: role_pod_lister,
});

// Services
local ingress_service = kube.Service('ingress-nginx') {
  metadata+: {
    namespace: 'ingress-nginx',
  },
  spec: {
    type: 'LoadBalancer',
    selector: {
      app: 'ingress-nginx',
    },
    ports: [{
      name: 'http',
      port: 80,
      targetPort: 80,
    }, {
      name: 'https',
      port: 443,
      targetPort: 443,
    }],
  }
};

// Define outputs below
{
  '00_namespace': namespace,
  '10a_secretkey': secretkey,
  '10b_config': configmap,
  '20a_controller_podsecuritypolicy': default_metadata(std.parseJson(kap.yaml_load('metallb/static/controller/podsecuritypolicy.yml'))),
  '20b_speaker_podsecuritypolicy': default_metadata(std.parseJson(kap.yaml_load('metallb/static/speaker/podsecuritypolicy.yml'))),
  '30a_speaker_serviceaccount': speaker_serviceaccount,
  '30b_controller_serviceaccount': controller_serviceaccount,
  '40a_controller_clusterrole': controller_clusterrole,
  '40b_speaker_clusterrole': speaker_clusterrole,
  '50a_controller_clusterrolebinding': controller_clusterrolebinding,  
  '50b_speaker_clusterrolebinding': speaker_clusterrolebinding,
  '60a_rolebinding_config_watcher': rolebinding_config_watcher,
  '60b_rolebinding_pod_lister': rolebinding_pod_lister,
  '70a_speaker_daemonset': default_metadata(std.parseJson(kap.yaml_load('metallb/static/speaker/daemonset.yml'))),
  '70b_controller_daemonset': default_metadata(std.parseJson(kap.yaml_load('metallb/static/controller/daemonset.yml'))),
  '80a_ingress_service': ingress_service,
}
