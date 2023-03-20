local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.metallb;

local metallb = import 'resources.libsonnet';

local deprecationMsg(param) =
  'Parameter `%s` is deprecated, please migrate to parameters ' % [ param ] +
  '`ipAddressPools`, `l2Advertisements`, `bgpPeers`, `bgpAdvertisements`, `communities`, and `bfdProfiles`.';

local convertConfigKey(k) =
  local keyparts = std.split(k, '-');
  std.join(
    '',
    std.mapWithIndex(
      function(idx, kp)
        if idx == 0 then kp
        else if std.member([ 'asn' ], kp) then
          'ASN'
        else
          local c = std.asciiUpper(kp[0]);
          c + kp[1:],
      keyparts
    )
  );


local ipAddressPools =
  if std.objectHas(params, 'addresses') && std.objectHas(params, 'config') then
    error 'Invalid config: The variables addresses and config can not be used at the same time!'
  else if std.objectHas(params, 'config') then std.trace(
    deprecationMsg('config'),
    std.mapWithIndex(
      function(idx, ap)
        metallb.IPAddressPool(ap.name) {
          metadata+: {
            annotations+: {
              'metallb.syn.tools/description':
                'This IP address pool is generated from the legacy parameter "config"',
            },
          },
          spec: {
            [convertConfigKey(k)]: ap[k]
            for k in std.objectFields(ap)
            if !std.member([ 'name', 'protocol', 'bgp-advertisements' ], k)
          },
        },
      params.config['address-pools']
    )
  )
  else [];

local l2Advertisement =
  local l2adv =
    metallb.L2Advertisement('legacy') {
      metadata+: {
        annotations+: {
          'metallb.syn.tools/description':
            'This L2Advertisement is generated if any L2 address pools are configured through the legacy configuration parameters',
        },
      },
      spec: {
        ipAddressPools:
          if std.objectHas(params, 'config') then
            [
              ap.name
              for ap in params.config['address-pools']
              if ap.protocol == 'layer2'
            ]
          else [],
      },
    };
  if std.length(l2adv.spec.ipAddressPools) > 0 then
    [ l2adv ]
  else [];

local bgpAdvertisements =
  if std.objectHas(params, 'config') then
    std.flattenArrays([
      if std.objectHas(ap, 'bgp-advertisements') then
        std.mapWithIndex(
          function(idx, adv)
            metallb.BGPAdvertisement('%s-%d' % [ ap.name, idx + 1 ]) {
              metadata+: {
                annotations+: {
                  'metallb.syn.tools/description':
                    'This advertisements is generated from legacy address pool config',
                },
              },
              spec: {
                ipAddressPools: [
                  ap.name,
                ],
              } + {
                [convertConfigKey(k)]: adv[k]
                for k in std.objectFields(adv)
                if k != 'localpref'
              } + {
                // fixup localpref field which wasn't kebab-case
                [if std.objectHas(adv, 'localpref') then 'localPref']:
                  adv.localpref,
              },
            },
          ap['bgp-advertisements']
        )
      else
        [
          metallb.BGPAdvertisement('%s-default' % ap.name) {
            metadata+: {
              annotations+: {
                'metallb.syn.tools/description':
                  'This advertisements is generated from legacy address pool config',
              },
            },
            spec: {
              ipAddressPools: [
                ap.name,
              ],
            },
          },
        ]
      for ap in params.config['address-pools']
      if ap.protocol == 'bgp'
    ])
  else
    [];

local community =
  if std.objectHas(params, 'config') then
    local coms = std.get(params.config, 'bgp-communities', {});
    if std.length(coms) > 0 then
      [
        metallb.Community('legacy') {
          metadata+: {
            annotations+: {
              'metallb.syn.tools/description':
                'This object is generated from the legacy config parameter',
            },
          },
          spec: {
            communities: [
              {
                name: cn,
                value: coms[cn],
              }
              for cn in std.objectFields(coms)
            ],
          },
        },
      ] else []
  else
    [];

local peers =
  local convertNodeSelectors(peer) =
    {
      [if std.objectHas(peer, 'node-selectors') then 'nodeSelectors']: [
        {
          [convertConfigKey(sel)]: ns[sel]
          for sel in std.objectFields(ns)
        }
        for ns in peer['node-selectors']
      ],
    };
  if std.objectHas(params, 'config') then
    std.mapWithIndex(
      function(idx, peer)
        metallb.BGPPeer('peer%d' % [ idx + 1 ]) {
          metadata+: {
            annotations+: {
              'metallb.syn.tools/description':
                'This BGP peer is generated from the legacy config parameter',
            },
          },
          spec: {
            [convertConfigKey(k)]: peer[k]
            for k in std.objectFields(peer)
            if k != 'node-selectors'
          } + convertNodeSelectors(peer),
        },
      std.get(params.config, 'peers', [])
    )
  else
    [];

local bfdProfiles =
  if std.objectHas(params, 'config') then
    local profiles = std.get(params.config, 'bfd-profiles', []);
    [
      metallb.BFDProfile(p.name) {
        metadata+: {
          annotations+: {
            'metallb.syn.tools/description':
              'This BFD profile is generated from the legacy config parameter',
          },
        },
        spec: {
          [convertConfigKey(k)]: p[k]
          for k in std.objectFields(p)
          if k != 'name'
        },
      }
      for p in profiles
    ]
  else
    [];

{
  BFDProfiles: bfdProfiles,
  BGPAdvertisements: bgpAdvertisements,
  BGPPeers: peers,
  Community: community,
  IPAddressPools: ipAddressPools,
  L2Advertisement: l2Advertisement,
}
