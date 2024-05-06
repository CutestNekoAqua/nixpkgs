{ config, lib, pkgs, utils, ... }:

with lib;

let
  cfg = config.services.kanata;

  upstreamDoc = "See [the upstream documentation](https://github.com/jtroo/kanata/blob/main/docs/config.adoc) and [example config files](https://github.com/jtroo/kanata/tree/main/cfg_samples) for more information.";

  keyboard = {
    options = {
      devices = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "/dev/input/by-id/usb-0000_0000-event-kbd" ];
        description = ''
          Paths to keyboard devices.

          An empty list, the default value, lets kanata detect which
          input devices are keyboards and intercept them all.
        '';
      };
      config = mkOption {
        type = types.lines;
        example = ''
          (defsrc
            caps)

          (deflayermap (default-layer)
            ;; tap caps lock as caps lock, hold caps lock as left control
            caps (tap-hold 100 100 caps lctl))
        '';
        description = ''
          Configuration other than `defcfg`.

          ${upstreamDoc}
        '';
      };
      extraDefCfg = mkOption {
        type = types.lines;
        default = "";
        example = "danger-enable-cmd yes";
        description = ''
          Configuration of `defcfg` other than `linux-dev` (generated
          from the devices option) and
          `linux-continue-if-no-devs-found` (hardcoded to be yes).

          ${upstreamDoc}
        '';
      };
      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra command line arguments passed to kanata.";
      };
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        example = 6666;
        description = ''
          Port to run the TCP server on. `null` will not run the server.
        '';
      };
    };
  };

  mkName = name: "kanata-${name}";

  mkDevices = devices:
    let
      devicesString = pipe devices [
        (map (device: "\"" + device + "\""))
        (concatStringsSep " ")
      ];
    in
    optionalString ((length devices) > 0) "linux-dev (${devicesString})";

  mkConfig = name: keyboard: pkgs.writeText "${mkName name}-config.kdb" ''
    (defcfg
      ${keyboard.extraDefCfg}
      ${mkDevices keyboard.devices}
      linux-continue-if-no-devs-found yes)

    ${keyboard.config}
  '';

  mkService = name: keyboard: nameValuePair (mkName name) {
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "notify";
      ExecStart = ''
        ${getExe cfg.package} \
          --cfg ${mkConfig name keyboard} \
          --symlink-path ''${RUNTIME_DIRECTORY}/${name} \
          ${optionalString (keyboard.port != null) "--port ${toString keyboard.port}"} \
          ${utils.escapeSystemdExecArgs keyboard.extraArgs}
      '';

      DynamicUser = true;
      RuntimeDirectory = mkName name;
      SupplementaryGroups = with config.users.groups; [
        input.name
        uinput.name
      ];

      # hardening
      DeviceAllow = [
        "/dev/uinput rw"
        "char-input r"
      ];
      CapabilityBoundingSet = [ "" ];
      DevicePolicy = "closed";
      IPAddressAllow = optional (keyboard.port != null) "localhost";
      IPAddressDeny = [ "any" ];
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      PrivateNetwork = keyboard.port == null;
      PrivateUsers = true;
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = [ "AF_UNIX" ] ++ optional (keyboard.port != null) "AF_INET";
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = [ "native" ];
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
      ];
      UMask = "0077";
    };
  };
in
{
  options.services.kanata = {
    enable = mkEnableOption "kanata, a tool to improve keyboard comfort and usability with advanced customization";
    package = mkPackageOption pkgs "kanata" {
      example = [ "kanata-with-cmd" ];
      extraDescription = ''
        ::: {.note}
        If {option}`danger-enable-cmd` is enabled in any of the keyboards, the
        `kanata-with-cmd` package should be used.
        :::
      '';
    };
    keyboards = mkOption {
      type = types.attrsOf (types.submodule keyboard);
      default = { };
      description = "Keyboard configurations.";
    };
  };

  config = mkIf cfg.enable {
    warnings =
      let
        keyboardsWithEmptyDevices = filterAttrs (name: keyboard: keyboard.devices == [ ]) cfg.keyboards;
        existEmptyDevices = length (attrNames keyboardsWithEmptyDevices) > 0;
        moreThanOneKeyboard = length (attrNames cfg.keyboards) > 1;
      in
      optional (existEmptyDevices && moreThanOneKeyboard) "One device can only be intercepted by one kanata instance.  Setting services.kanata.keyboards.${head (attrNames keyboardsWithEmptyDevices)}.devices = [ ] and using more than one services.kanata.keyboards may cause a race condition.";

    hardware.uinput.enable = true;

    systemd.services = mapAttrs' mkService cfg.keyboards;
  };

  meta.maintainers = with maintainers; [ linj ];
}
