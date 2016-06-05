"""Get version information for Neovim's python-client.

Prints four lines:
  - Python Version
  - Current Version
  - Latest Version
  - Version Status

Errors are suppressed unless the `--debug` switch is present.
"""
import os
import re
import sys
import json
import itertools

from glob import glob
from distutils.version import LooseVersion

try:
    from urllib.request import urlopen
except ImportError:
    from urllib2 import urlopen


def nvim_version():
    try:
        import neovim

        nvim_dir = os.path.dirname(neovim.__file__)
    except ImportError:
        if '--debug' in sys.argv:
            raise
        return 'unknown'

    for file in itertools.chain(glob('%s-*/METADATA' % nvim_dir),
                                glob('%s-*/PKG-INFO' % nvim_dir)):
        with open(file, 'rt') as fp:
            m = re.search('^Version: (\S+)$', fp.read(), re.M)
            if m:
                return m.group(1)
    return 'unknown'


def nvim_latest():
    response = urlopen('https://pypi.python.org/pypi/neovim/json')
    pkg_info = json.loads(response.read().decode('utf8'))
    return pkg_info.get('info', {}).get('version', 'unknown')


def nvim_info_run():
    version = nvim_version()

    try:
        latest = nvim_latest()
    except Exception:
        if '--debug' in sys.argv:
            raise
        latest = 'unknown'

    info = [
        '.'.join(str(x) for x in sys.version_info[:3]),
        version,
        latest,
    ]

    if 'unknown' not in (version, latest):
        info.append('up to date'
                    if LooseVersion(version) >= LooseVersion(latest)
                    else 'outdated')
    else:
        info.append('unknown')

    if 'VIM' in os.environ:
        try:
            import vim
            vim.command('let version_info = %s' % json.dumps(info))
            return
        except ImportError:
            pass

    print('\n'.join(info))


if __name__ == "__main__":
    nvim_info_run()
