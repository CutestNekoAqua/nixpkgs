{ lib
, stdenv
, fetchFromGitea
, fetchYarnDeps
, fixup_yarn_lock
, yarn
, nodejs
, python3
, pkg-config
, glib
, vips
, cargo
, rustPlatform
, rustc
, napi-rs-cli
, libiconv
, rome
, swc
, cypress
, nodePackages
, esbuild
}:

let
  version = "nightly230729";

  src = fetchFromGitea {
    domain = "iceshrimp.dev";
    owner = "iceshrimp";
    repo = "iceshrimp";
    rev = version;
    hash = "sha256-V1f13Tmt63RdUVJgQOniAJCGBBB+rKYqE+KzqPM2NR4=";
  };

  unplugged = fetchFromGitea {
    domain = "iceshrimp.dev";
    owner = "iceshrimp";
    repo = "unplugged-dist";
    rev = version;
    hash = "sha256-zea2OA4lkjPL+8V3gEvC40/6r1dXhA9kDD7n6kBrSz8=";
  };
in stdenv.mkDerivation {
  pname = "iceshrimp";
  inherit version src;

  cargoRoot = "packages/backend/native-utils";

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${src}/packages/backend/native-utils/Cargo.lock";
  };

  nativeBuildInputs = [
    fixup_yarn_lock 
    yarn
    nodejs 
    python3 
    pkg-config 
    rustPlatform.cargoSetupHook
    cargo
    rustc
    napi-rs-cli
    rome
    swc
    cypress
    nodePackages.node-gyp
    esbuild
  ];
  buildInputs = [ glib vips unplugged ]
    ++ lib.optionals stdenv.isDarwin [ libiconv ];

  buildPhase = ''
    export HOME=$PWD
    export NODE_ENV=production
    mkdir .yarn/unplugged
    cp -r ${unplugged} .yarn/unplugged
    runHook preBuild
    # Build node modules
    fixup_yarn_lock yarn.lock
    #fixup_yarn_lock packages/backend/yarn.lock
    #fixup_yarn_lock packages/client/yarn.lock
    #yarn install --frozen-lockfile --ignore-engines --ignore-scripts --no-progress
    (
      cd packages/iceshrimp-js
      swc compile src --out-dir built
      mv built/src/* built/
    )
    (
      cd packages/backend/native-utils
      napi build --features napi --platform --release --cargo-flags \\-\-offline ./built/
      cargo build --locked --release --offline --manifest-path ./migration/Cargo.toml && cp ./target/release/migration ./built/migration
    )
    #(
    #  cd packages/client
    #  yarn config --offline set yarn-offline-mirror
    #  yarn install --offline --frozen-lockfile --ignore-engines --ignore-scripts --no-progress
    #)
    #patchShebangs node_modules
    #patchShebangs packages/backend/node_modules
    #patchShebangs packages/client/node_modules
    #(
    #  cd packages/backend/node_modules/re2
    #  npm_config_nodedir=${nodejs} npm run rebuild
    #)
    #(
    #  cd packages/backend/node_modules/sharp
    #  npm_config_nodedir=${nodejs} ../.bin/node-gyp rebuild
    #)
    yarn workspace megalodon run build
    yarn workspace sw run build
    yarn workspace client run build
    yarn workspace backend run build
    yarn gulp

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/packages/client
    ln -s /var/lib/misskey $out/files
    ln -s /run/misskey $out/.config
    cp -r locales node_modules built $out
    cp -r packages/backend $out/packages/backend
    cp -r packages/client/assets $out/packages/client/assets

    runHook postInstall
  '';

  meta = with lib; {
    description = "Yet Another Misskey Fork (YAMF) since 2023 🚀";
    homepage = "https://iceshrimp.dev/";
    license = licenses.agpl3;
    maintainers = with maintainers; [ aprl ];
    inherit (nodejs.meta) platforms;
  };
}
