local com = import 'lib/commodore.libjsonnet';

local dir = std.extVar('output_path');

// fixupDir already drops `null` objects, so we can just give the identity
// function as the 2nd argument.
com.fixupDir(dir, function(o) o)
