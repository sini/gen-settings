# T7 injection-wrap (L12, L13). Always-wrap totality across the three module shapes, and the
# namespaced binding. The Spike 5 firewall full loop is the fixed corpus: kebab schema keys →
# resolved `allowed-tcp` → wrapped nixos content → evalModules with stub options → the option value
# equals the cascade output. Plus mkDefault survival, bindWins shadowing, and a second aspect.
{
  lib,
  genSettings,
  ...
}:
let
  inherit (genSettings)
    mkSchema
    resolveOne
    injectAspectSettings
    ;
  fx = import ./_fixtures/fixtures.nix { inherit lib; };

  fwSchema = mkSchema {
    aspect = fx.aspects.firewall;
    fields = {
      "allowed-tcp" = {
        default = [ 22 ];
        merge = "append";
      };
    };
  };
  fwSettings =
    (resolveOne {
      schema = fwSchema;
      layers = [
        (fx.mkLayer {
          value = {
            "allowed-tcp" = [ 80 ];
          };
        })
        (fx.mkLayer {
          value = {
            "allowed-tcp" = [ 443 ];
          };
        })
      ];
    }).value;
  expectedPorts = [
    22
    80
    443
  ];

  fwOpts = {
    options.networking.firewall.allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.int;
      default = [ ];
    };
  };
  # Content reads settings.<settingsKey>.<field> — here settings.firewall."allowed-tcp".
  fwFn =
    { settings, ... }:
    {
      config.networking.firewall.allowedTCPPorts = settings.firewall."allowed-tcp";
    };

  evalPortsOf =
    module:
    (lib.evalModules {
      modules = [
        fwOpts
        module
      ];
    }).config.networking.firewall.allowedTCPPorts;

  injFn = injectAspectSettings {
    aspect = fx.aspects.firewall;
    classContent = fwFn;
    settings = fwSettings;
  };
  injImports = injectAspectSettings {
    aspect = fx.aspects.firewall;
    classContent = {
      imports = [ fwFn ];
    };
    settings = fwSettings;
  };
  plainContent = {
    config.networking.firewall.allowedTCPPorts = [
      1
      2
    ];
  };
  injPlain = injectAspectSettings {
    aspect = fx.aspects.firewall;
    classContent = plainContent;
    settings = fwSettings;
  };

  # mkDefault survival: a stripped default would conflict with the override; mkDefault ranks below it.
  valOpts = {
    options.val = lib.mkOption {
      type = lib.types.int;
      default = 0;
    };
  };
  mkDefFn =
    { settings, lib, ... }:
    {
      config.val = lib.mkDefault 5;
    };
  injMkDef = injectAspectSettings {
    aspect = fx.aspects.firewall;
    classContent = mkDefFn;
    settings = fwSettings;
  };
  valEval =
    (lib.evalModules {
      modules = [
        valOpts
        injMkDef.module
        { config.val = 9; }
      ];
    }).config.val;

  # bindWins: an injected `host` binding shadows a stray same-named module arg.
  hostOpts = {
    options.hostName = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };
  bindWinsFn =
    { settings, host, ... }:
    {
      config.hostName = host.name;
    };
  injBindWins = injectAspectSettings {
    aspect = fx.aspects.firewall;
    classContent = bindWinsFn;
    settings = fwSettings;
    bindings = {
      host = fx.entities.axon;
    };
  };
  hostEval =
    (lib.evalModules {
      modules = [
        hostOpts
        injBindWins.module
      ];
    }).config.hostName;

  # Second aspect (nginx-style): scalar + recursive, proving non-specificity to one aspect.
  nginxSchema = mkSchema {
    aspect = fx.aspects.nginx;
    fields = {
      worker = {
        default = 1;
      };
      extra = {
        default = {
          gzip = true;
        };
        merge = "recursive";
      };
    };
  };
  nginxSettings =
    (resolveOne {
      schema = nginxSchema;
      layers = [
        (fx.mkLayer {
          value = {
            worker = 4;
          };
        })
      ];
    }).value;
  nginxOpts = {
    options.workers = lib.mkOption {
      type = lib.types.int;
      default = 0;
    };
  };
  injNginx = injectAspectSettings {
    aspect = fx.aspects.nginx;
    classContent =
      { settings, ... }:
      {
        config.workers = settings.nginx.worker;
      };
    settings = nginxSettings;
  };
  nginxEval =
    (lib.evalModules {
      modules = [
        nginxOpts
        injNginx.module
      ];
    }).config.workers;
in
{
  flake.tests.injection-wrap = {
    # L12 — always-wrap totality across the three shapes.
    test-fn-wrapped = {
      expr = injFn.wrapped;
      expected = true;
    };
    test-imports-wrapped = {
      expr = injImports.wrapped;
      expected = true;
    };
    test-plain-passthrough = {
      expr = injPlain.wrapped;
      expected = false;
    };
    test-plain-byte-identical = {
      expr = injPlain.module == plainContent;
      expected = true;
    };

    # L13 — the firewall full loop: cascade output flows through the wrapped module into evalModules.
    test-fn-full-loop = {
      expr = evalPortsOf injFn.module;
      expected = expectedPorts;
    };
    test-imports-full-loop = {
      expr = evalPortsOf injImports.module;
      expected = expectedPorts;
    };

    # L13 — mkDefault survives wrapping (override wins, no conflict).
    test-mkdefault-survives = {
      expr = valEval;
      expected = 9;
    };
    # L13 — bindWins: injected host shadows the module arg; content observes it.
    test-bindwins-host = {
      expr = hostEval;
      expected = "axon-01";
    };
    # Non-specificity: a second aspect with a different schema shape injects the same way.
    test-second-aspect = {
      expr = nginxEval;
      expected = 4;
    };
  };
}
