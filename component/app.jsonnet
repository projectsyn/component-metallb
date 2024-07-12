local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.metallb;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('metallb', params.namespace) {
  spec+: {
    ignoreDifferences: [
      {
        group: 'apiextensions.k8s.io',
        kind: 'CustomResourceDefinition',
        jsonPointers: [
          '/spec/conversion/webhook/clientConfig/caBundle',
        ],
      },
    ],
  },
};

{
  metallb: app,
}
