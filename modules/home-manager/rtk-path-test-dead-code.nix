{ pkgs }:

pkgs.rtk.overrideAttrs (oldAttrs: {
  postPatch = (oldAttrs.postPatch or "") + ''
        substituteInPlace src/core/constants.rs \
          --replace-fail \
            'pub const FILTERS_TOML: &str = "filters.toml";' \
            '#[cfg_attr(test, allow(dead_code))]
    pub const FILTERS_TOML: &str = "filters.toml";'

        substituteInPlace src/core/toml_filter.rs \
          --replace-fail \
            '    fn load() -> Self {' \
            '    #[cfg_attr(test, allow(dead_code))]
        fn load() -> Self {'
  '';
})
