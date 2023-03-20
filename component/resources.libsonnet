local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.metallb;

local cr(kind, name) =
  kube._Object('metallb.io/v1beta1', kind, name) {
    metadata+: {
      namespace: params.namespace,
    },
  };

{
  BFDProfile: function(name) cr('BFDProfile', name),
  BGPAdvertisement: function(name) cr('BGPAdvertisement', name),
  BGPPeer: function(name) cr('BGPPeer', name) {
    // BGPPeer has different API version than the other custom resources
    apiVersion: 'metallb.io/v1beta2',
  },
  Community: function(name) cr('Community', name),
  IPAddressPool: function(name) cr('IPAddressPool', name),
  L2Advertisement: function(name) cr('L2Advertisement', name),
}
