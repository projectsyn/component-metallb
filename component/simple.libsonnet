local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.metallb;

local metallb = import 'resources.libsonnet';

local pool = metallb.IPAddressPool('default') {
  metadata+: {
    annotations+: {
      'metallb.syn.tools/description':
        'This IP address pool is generated from the legacy parameter "addresses"',
    },
  },
  spec: {
    addresses: std.get(params, 'addresses', []),
  },
};

local advertisement =
  metallb.L2Advertisement('default') {
    spec: {
      ipAddressPools: [ pool.metadata.name ],
    },
  };

{
  ipPool: pool,
  l2Advertisement: advertisement,
  present: std.objectHas(params, 'addresses'),
}
