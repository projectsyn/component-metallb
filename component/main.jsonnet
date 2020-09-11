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

// Services
local ingress_nginx_service = kube.Service('ingress-nginx') {
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
  [if params.memberlist_secretkey != "" then '01_memberlist_secret']: memberlist_secret,
  [if params.ingress_nginx_service then '20_ingress_service']: ingress_nginx_service,
}
