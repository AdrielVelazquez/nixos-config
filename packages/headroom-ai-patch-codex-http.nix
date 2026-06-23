{ pythonSitePackages }:

''
  substituteInPlace "$out/${pythonSitePackages}/headroom/cli/init.py" \
    --replace-fail 'supports_websockets = true' 'supports_websockets = false'
  substituteInPlace "$out/${pythonSitePackages}/headroom/providers/codex/install.py" \
    --replace-fail 'supports_websockets = true' 'supports_websockets = false'
''
