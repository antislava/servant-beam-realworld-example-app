import ./nixpkgs {
  config = {
    packageOverrides = pkgs:
      with pkgs.haskell.lib;
      let
        composeExtensionsList =
               pkgs.lib.fold pkgs.lib.composeExtensions (_: _: {});
        nc   = dontCheck;
          jb = doJailbreak;
        ncjb = p: nc (jb p);
        overrides1 = self: super: {
          inherit (import ./beam pkgs self super)
            beam-core
            beam-postgres
            beam-migrate;
          inherit (import ./base-noprelude pkgs self super)
            base-noprelude;
        };
        overrides2 = self: super: {
          beam-core                 = ncjb super.beam-core;
          insert-ordered-containers = ncjb super.insert-ordered-containers;
        };
      in {
      haskellPackages = pkgs.haskellPackages.override {
        overrides = composeExtensionsList [
          overrides1
          overrides2
        ];
      };
    };
  };
}
