// main template for metallb
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.metallb;

local metallb = import 'resources.libsonnet';
local legacy = import 'legacy.libsonnet';
local simple = import 'simple.libsonnet';

local metallbVersion =
  local ver = params.charts.metallb.version;
  local verparts = std.split(ver, '.');
  local parseOrError(val, typ) =
    local parsed = std.parseJson(val);
    if std.isNumber(parsed) then
      parsed
    else
      error
        'Failed to parse %s version "%s" as number' % [
          typ,
          val,
        ];
  {
    major: parseOrError(verparts[0], 'major'),
    minor: parseOrError(verparts[1], 'minor'),
  };


assert
  metallbVersion.major >= 1 || (metallbVersion.major == 0 && metallbVersion.minor >= 13) :
  'Component metallb %s only supports MetalLB 0.13 and newer' %
  [ inv.parameters.components.metallb.version ];

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: {
      app: 'metallb',
      'app.kubernetes.io/name': 'metallb',
      'app.kubernetes.io/instance': 'metallb',
    },
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

local ipAddressPools =
  local default_pool = simple.ipPool;
  local pools =
    legacy.IPAddressPools +
    com.generateResources(
      params.ipAddressPools {
        [if simple.present then default_pool.metadata.name]+: {
          spec+: {
            addresses+: [],
          },
        },
      },
      metallb.IPAddressPool
    );

  [
    if
      simple.present &&
      p.metadata.name == default_pool.metadata.name
    then
      p {
        spec+: {
          addresses+: [
            range
            for range in default_pool.spec.addresses
            if !std.member(p.spec.addresses, range)
          ],
        },
      }
    else
      p
    for p in pools
  ];

local l2Advertisements =
  local simple_adv = simple.l2Advertisement;
  local advertisements =
    legacy.L2Advertisement +
    com.generateResources(
      params.l2Advertisements {
        [if simple.present then simple_adv.metadata.name]+: {
          spec+: {
            ipAddressPools+: [],
          },
        },
      },
      metallb.L2Advertisement
    );

  [
    if
      simple.present &&
      adv.metadata.name == simple_adv.metadata.name
    then
      adv {
        spec+: {
          ipAddressPools+: [
            p
            for p in simple_adv.spec.ipAddressPools
            if !std.member(adv.spec.ipAddressPools, p)
          ],
        },
      }
    else
      adv
    for adv in advertisements
  ];

local bgpPeers =
  legacy.BGPPeers +
  com.generateResources(
    params.bgpPeers,
    metallb.BGPPeer
  );

local bgpAdvertisements =
  legacy.BGPAdvertisements +
  com.generateResources(
    params.bgpAdvertisements,
    metallb.BGPAdvertisement
  );

local communities =
  legacy.Community +
  com.generateResources(
    params.communities,
    metallb.Community
  );

local bfdProfiles =
  legacy.BFDProfiles +
  com.generateResources(
    params.bfdProfiles,
    metallb.BFDProfile,
  );

local validatePeers(peers) =
  local frrEnabled = std.get(
    params.helm_values.speaker,
    'frr',
    { enabled: false }
  ).enabled;
  if frrEnabled then
    peers
  else
    [
      if std.objectHas(peer.spec, 'bfdProfile') then
        std.trace(
          "Peer '%s' has a BFD profile configured, " % peer.metadata.name +
          "but the MetalLB speakers aren't configured in FRR mode. " +
          'This configuration will fail to apply on the cluster.',
          peer
        )
      else
        peer
      for peer in peers
    ];

// Define outputs below
{
  '00_namespace': namespace,
  [if params.memberlist_secretkey != '' then '01_memberlist_secret']: memberlist_secret,
  // ordering matches the output of the upstream configmap->cr conversion tool
  // for easier validation of our own conversion logic.
  '02_config':
    validatePeers(bgpPeers) +
    ipAddressPools +
    bgpAdvertisements +
    l2Advertisements +
    bfdProfiles +
    communities,
}
