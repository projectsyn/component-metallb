// main template for metallb
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.metallb;

local metallbVersion =
  local ver = params.charts.metallb.version;
  local verparts = std.split(ver, '.');
  local parseOrWarn(val, typ) =
    local parsed = std.parseJson(val);
    if std.isNumber(parsed) then
      parsed
    else
      std.trace(
        'Failed to parse %s version "%s" as number, returning 0' % [ typ, val ],
        0
      );
  {
    major: parseOrWarn(verparts[0], 'major'),
    minor: parseOrWarn(verparts[1], 'minor'),
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

local configmap = kube.ConfigMap(params.configmap_name) {
  metadata+: {
    namespace: params.namespace,
  },
  data: {
    config:
      if std.objectHas(params, 'addresses') && std.objectHas(params, 'config') then
        error 'Invalid config: The variables addresses and config can not be used at the same time!'
      else if std.objectHas(params, 'addresses') then std.manifestYamlDoc({
        'address-pools': [
          {
            name: 'default',
            protocol: 'layer2',
            addresses: params.addresses,
          },
        ],
      })
      else if std.objectHas(params, 'config') then std.manifestYamlDoc(params.config)
      else error 'The addresses array must contain at least one virtual IP or an override config must be configured!',
  },
};

// Define outputs below
{
  '00_namespace': namespace,
  [if params.memberlist_secretkey != '' then '01_memberlist_secret']: memberlist_secret,
  '02_configmap': configmap,
}
