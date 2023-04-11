{
  description = "Application packaged using poetry2nix";

  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.poetry2nix = {
    url = "github:nix-community/poetry2nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, flake-utils, poetry2nix }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # see https://github.com/nix-community/poetry2nix/tree/master#api for more functions and examples.
        inherit (poetry2nix.legacyPackages.${system}) mkPoetryApplication;
        inherit (poetry2nix.legacyPackages.${system}) mkPoetryEnv;
        pkgs = nixpkgs.legacyPackages.${system};

        poetryOverrides = pkgs.poetry2nix.overrides.withDefaults 
          (self: super:
            let
              pyBuildPackages = self.python.pythonForBuild.pkgs;
            in
          {
            elpy = super.elpy.overridePythonAttrs
            (
              old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
              }
            );

            # The following are dependencies of torch >= 2.0.0.
            # torch doesn't officially support system CUDA, unless you build it yourself.
            nvidia-cudnn-cu11 = super.nvidia-cudnn-cu11.overridePythonAttrs (attrs: {
              autoPatchelfIgnoreMissingDeps = true;
              # (Bytecode collision happens with nvidia-cuda-nvrtc-cu11.)
              postFixup = ''
                rm -r $out/${self.python.sitePackages}/nvidia/{__pycache__,__init__.py}
              '';
              propagatedBuildInputs = attrs.propagatedBuildInputs or [ ] ++ [
                super.nvidia-cublas-cu11
              ];
            });

            nvidia-cuda-nvrtc-cu11 = super.nvidia-cuda-nvrtc-cu11.overridePythonAttrs (_: {
              # (Bytecode collision happens with nvidia-cudnn-cu11.)
              postFixup = ''
                rm -r $out/${self.python.sitePackages}/nvidia/{__pycache__,__init__.py}
              '';
            });

            nvidia-cusolver-cu11 = super.nvidia-cusolver-cu11.overridePythonAttrs (attrs: {
              autoPatchelfIgnoreMissingDeps = true;
              # (Bytecode collision happens with nvidia-cusolver-cu11.)
              postFixup = ''
                rm -r $out/${self.python.sitePackages}/nvidia/{__pycache__,__init__.py}
              '';
              propagatedBuildInputs = attrs.propagatedBuildInputs or [ ] ++ [
                super.nvidia-cublas-cu11
              ];
            });

            # Circular dependency between triton and torch (see https://github.com/openai/triton/issues/1374)
            # You can remove this once triton publishes a new stable build and torch takes it.
            triton = super.triton.overridePythonAttrs (old: {
              propagatedBuildInputs = builtins.filter (e: e.pname != "torch") old.propagatedBuildInputs;
              pipInstallFlags = [ "--no-deps" ];
            });


            lit = super.lit.overridePythonAttrs
            (
              old: {
                buildInputs = (old.buildInputs or [ ]) ++ [ super.setuptools ];
              }
            );

            torch = super.torch.overridePythonAttrs (old: {
              # torch has an auto-magical way to locate the cuda libraries from site-packages.
              autoPatchelfIgnoreMissingDeps = true;
              propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
                self.numpy
                self.nvidia-cudnn-cu11
              ];
              buildInputs = (old.buildInputs or [ ]) ++ [
                self.nvidia-cudnn-cu11
                self.nvidia-cuda-nvrtc-cu11
                self.nvidia-cuda-runtime-cu11
                self.nvidia-cufft-cu11
                self.nvidia-nccl-cu11
                super.sympy
                super.jinja2
                super.nvidia-cuda-cupti-cu11
                super.nvidia-cusparse-cu11
                super.networkx
                super.nvidia-curand-cu11
                super.filelock
                self.triton
                self.nvidia-cusolver-cu11
                super.nvidia-nvtx-cu11
              ];
            });

            # fastbook overrides
            pip = pkgs.python310Packages.pip;
            pybind11 = pkgs.python310Packages.pybind11;
            torchvision = pkgs.python310Packages.torchvision;
            # pycodestyle = super.pycodestyle.overridePythonAttrs( old: {
            #   nativeBuildInputs = builtins.filter (p: p.name != "pip-install-hook") old.nativeBuildInputs;
            # });
            # vkbottle-types = prev.vkbottle-types.overridePythonAttrs (old: {
            #   propagatedBuildInputs = builtins.filter (p: p.pname != "vkbottle") old.propagatedBuildInputs;
            #   buildInputs = (old.buildInputs or [ ]) ++ [ final.poetry ];
            #   postPatch = '' substituteInPlace pyproject.toml --replace 'vkbottle = "^4.3.5"' "" ''; });


          });
        poetryEnv = mkPoetryEnv {
          projectDir = ./.;
          overrides = poetryOverrides;
          preferWheels = true;
        };
      in
      {
        packages = {
          myapp = mkPoetryApplication {
            projectDir = self;
            overrides = poetryOverrides;
            preferWheels = true;
          };
          default = self.packages.${system}.myapp;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            poetryEnv
          ];
          packages = [
            poetry2nix.packages.${system}.poetry
          ];
          shellHook = ''
            export LD_PRELOAD="/run/opengl-driver/lib/libcuda.so"
          '';
        };
      });
}
