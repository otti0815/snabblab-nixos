{ config, pkgs, lib, ... }:

{
  require = [
    ./users.nix
    ./sudo-in-builds.nix
    ./munin-node.nix
  ];

  i18n.defaultLocale = "en_US.UTF-8";

  # extend nixpkgs with our own package
  nixpkgs.config.packageOverrides = pkgs: {
    inherit (import ./../pkgs { inherit pkgs; }) snabbpkgs;
  };

  # let's make sure only NixOS can handle users
  users.mutableUsers = false;

  # less paranoia
  networking.firewall.allowPing = true;

  # https://github.com/NixOS/nixpkgs/issues/10101
  networking.firewall.checkReversePath = false;

  # see https://github.com/NixOS/nixpkgs/commit/ee8e15fe76a235ae3583d4e8cb4bb370f28c5eae
  programs.bash.enableCompletion = true;

  environment.systemPackages = with pkgs; [
    # develoment tools
    gcc glibc git gnumake wget nmap screen tmux pciutils tcpdump curl strace htop
    file cpulimit numactl speedtest-cli w3m psmisc xterm wgetpaste
    config.boot.kernelPackages.perf nox ipmitool nixops ncdu
    # manpages
    manpages
    posix_man_pages
    # editors
    vim
    (emacsWithPackages (epkgs: [ epkgs.lua-mode ]))
    snabbpkgs.lock
  ];

  nix = rec {
    # use nix sandboxing for greater determinism
    useChroot = true;

    # make sure we have enough build users
    nrBuildUsers = 30;

    # if our hydra is down, don't wait forever
    extraOptions = ''
      connect-timeout = 10
    '';

    # use our hydra builds
    trustedBinaryCaches = [ "https://cache.nixos.org" "https://hydra.snabb.co" ];
    binaryCaches = trustedBinaryCaches;
    binaryCachePublicKeys = [ "hydra.snabb.co-1:zPzKSJ1mynGtYEVbUR0QVZf9TLcaygz/OyzHlWo5AMM=" ];
  };

  # allow users to use nix-env/nix-shell
  systemd.services.nixos-update = {
     description = "NixOS Upgrade";
     unitConfig.X-StopOnRemoval = false;
     serviceConfig.Type = "oneshot";

     environment = config.nix.envVars //
       { inherit (config.environment.sessionVariables) NIX_PATH;
         HOME = "/root";
       };
     path = [ pkgs.gnutar pkgs.xz config.nix.package.out ];
     script = ''
       nix-channel --add http://nixos.org/channels/nixos-16.03 nixos
       nix-channel --update nixos
     '';
     startAt = "05:40";
   };

  # Auto upgrade NixOS
  system.autoUpgrade.enable = true;
  system.autoUpgrade.dates = "*:0/10";
  systemd.services.nixos-upgrade.environment.NIX_PATH = "/nix/var/nix/profiles/per-user/root/channels/snabblab/:/nix/var/nix/profiles/per-user/root/channels/";
  systemd.services.nixos-upgrade.environment.NIXOS_CONFIG = pkgs.writeText "configuration.nix" ''
    (import <snabblab/machines>).${config.networking.hostName}.config
  '';
  system.activationScripts.snabblab = ''
    export PATH=$PATH:${pkgs.gnutar}/bin:${pkgs.xz}/bin
    NIX_PATH= /run/current-system/sw/bin/nix-channel --remove nixos
    NIX_PATH= /run/current-system/sw/bin/nix-channel --add https://hydra.snabb.co/channel/custom/domenkozar-sandbox/snabblab/machines.${config.networking.hostName} snabblab
    NIX_PATH= /run/current-system/sw/bin/nix-channel --update
  '';

  # Expose machines for Hydra slaves
  programs.ssh.extraConfig = ''
    Host grindelwald.snabb.co
        Hostname lab1.snabb.co
        Port 2010

    Host interlaken.snabb.co
        Hostname lab1.snabb.co
        Port 2030

    Host davos.snabb.co
        Hostname lab1.snabb.co
        Port 2000
  '';

  # lets users use sudo without password
  security.sudo.wheelNeedsPassword = false;

  # direct root access with pub key
  users.extraUsers.root.openssh.authorizedKeys.keys = config.users.extraUsers.domenkozar.openssh.authorizedKeys.keys;
}
