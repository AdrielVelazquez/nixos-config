{
  lib,
  root ? ../.,
}:
let
  source =
    paths:
    lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions (map (path: root + "/${path}") paths);
    };
  matching = extension: lib.fileset.fileFilter (file: file.hasExt extension) root;
in
{
  snoocert-bundle = source [
    "tests/snoocert-bundle.sh"
    "modules/system/snoocert-bundle.sh"
    "modules/home-manager/snoocert-import.sh"
  ];
  justfile-contract = source [
    "tests/justfile-contract.sh"
    "justfile"
  ];
  nvim-regressions = source [
    "tests/nvim"
    "dotfiles/nvim"
  ];
  pi-base = source [
    "tests/pi/workflow.mjs"
    "tests/pi/question.mjs"
    "dotfiles/pi/extensions/question.ts"
    "dotfiles/pi/extensions/question-core.ts"
    "dotfiles/pi/extensions/question-ui.ts"
    "dotfiles/pi/extensions/opencode-ui-core.ts"
  ];
  pi-capabilities = source [
    "tests/pi/capabilities.mjs"
    "tests/pi/capability-host.mjs"
  ];
  pi-checkpoints = source [
    "tests/pi/checkpoint-core.test.mjs"
    "tests/pi/checkpoint.test.mjs"
    "tests/pi/checkpoint-session.py"
    "tests/pi/scripted_pi.py"
    "dotfiles/pi/extensions/checkpoint-core.ts"
    "dotfiles/pi/extensions/checkpoint.ts"
  ];
  pi-dap = source [
    "tests/pi/dap-session.py"
  ];
  pi-eval = source [
    "tests/pi/eval-kernel.test.mjs"
    "tests/pi/eval-session.py"
    "dotfiles/pi/eval/runner.py"
    "dotfiles/pi/extensions/eval-core.ts"
    "dotfiles/pi/extensions/eval-kernel.ts"
  ];
  pi-format = source [
    "tests/pi/format-core.test.mjs"
    "tests/pi/format-on-write.test.mjs"
    "tests/pi/bash-changes.test.mjs"
    "tests/pi/format-contract.mjs"
    "tests/pi/bash-format-session.py"
    "tests/pi/format-order.py"
    "tests/pi/ast-rewrite-format.py"
    "tests/pi/scripted_pi.py"
    "dotfiles/pi/extensions/format-core.ts"
    "dotfiles/pi/extensions/format-on-write.ts"
    "dotfiles/pi/extensions/bash-changes-core.ts"
  ];
  pi-hashline = source [
    "tests/pi/hashline-session.py"
  ];
  pi-headroom = source [
    "tests/headroom-pi.py"
    "tests/pi/fake-headroom.py"
    "tests/pi/headroom-hooks.mjs"
    "tests/pi/headroom-worktrees.mjs"
    "tests/pi/headroom-children.mjs"
    "tests/pi/headroom.mjs"
    "tests/pi/blob.ts"
    "packages/headroom-pi.py"
    "dotfiles/pi/extensions/headroom.ts"
    "dotfiles/pi/extensions/headroom-children.ts"
    "dotfiles/pi/extensions/headroom-codex.ts"
    "dotfiles/pi/extensions/model-roles.ts"
    "dotfiles/pi/extensions/role-core.ts"
  ];
  pi-headroom-codex = source [
    "tests/pi/headroom-codex.test.mjs"
    "tests/pi/headroom-codex.mjs"
    "packages/headroom-pi.py"
    "dotfiles/pi/extensions/headroom-codex.ts"
    "dotfiles/pi/extensions/headroom.ts"
    "dotfiles/pi/extensions/headroom-children.ts"
  ];
  pi-headroom-providers = source [
    "tests/pi/headroom-providers.test.mjs"
    "tests/pi/headroom-hooks.mjs"
    "tests/pi/headroom-providers.mjs"
    "packages/headroom-pi.py"
    "dotfiles/pi/extensions/headroom-providers.ts"
    "dotfiles/pi/extensions/headroom.ts"
    "dotfiles/pi/extensions/headroom-children.ts"
  ];
  pi-jobs = source [
    "tests/pi/jobs-session.py"
    "tests/pi/scripted_pi.py"
    "tests/pi/fixtures/background-probe.ts"
  ];
  pi-model-roles = source [
    "tests/pi/role-core.test.mjs"
    "tests/pi/model-roles.test.mjs"
    "tests/pi/model-roles-contract.mjs"
    "tests/pi/model-roles-pty.py"
    "tests/pi/model-roles-fixture.ts"
    "dotfiles/pi/planning-instructions.md"
    "dotfiles/pi/extensions/model-roles.ts"
    "dotfiles/pi/extensions/role-core.ts"
  ];
  pi-routing = source [
    "tests/pi/role-core.test.mjs"
    "tests/pi/model-roles.test.mjs"
    "tests/pi/roles.mjs"
    "tests/pi/required-integrations.mjs"
    "tests/pi/routing.mjs"
    "tests/pi/fixtures"
    "tests/pi/fake-headroom.py"
    "packages/headroom-pi.py"
    "dotfiles/pi/extensions/model-roles.ts"
    "dotfiles/pi/extensions/role-core.ts"
    "dotfiles/pi/extensions/headroom.ts"
    "dotfiles/pi/extensions/headroom-children.ts"
    "dotfiles/pi/extensions/required-integrations.ts"
  ];
  pi-rtk = source [
    "tests/pi/rtk-session.py"
    "tests/pi/scripted_pi.py"
  ];
  pi-tools = source [
    "tests/pi/todo-core.test.mjs"
    "tests/pi/todo-features.test.mjs"
    "tests/pi/todo.test.mjs"
    "tests/pi/todo-session.py"
    "tests/pi/todo-ui.py"
    "tests/pi/tools-session.py"
    "tests/pi/scripted_pi.py"
    "dotfiles/pi/extensions/todo-core.ts"
    "dotfiles/pi/extensions/todo.ts"
    "dotfiles/pi/extensions/todo-i18n.ts"
  ];
  pi-tuios = source [
    "tests/pi/tuios.mjs"
    "tests/pi/tuios-outcomes.mjs"
    "dotfiles/pi/extensions/tuios-outcomes.ts"
  ];
  pi-ui = source [
    "tests/pi/ui-contract.mjs"
    "tests/pi/ui-neutral-foreground.test.mjs"
    "tests/pi/opencode-ui.test.mjs"
    "dotfiles/pi/themes"
    "dotfiles/pi/extensions/neutral-foreground.ts"
    "dotfiles/pi/extensions/opencode-ui.ts"
    "dotfiles/pi/extensions/opencode-ui-core.ts"
  ];
  pi-web-search = source [
    "tests/pi/search-cooldown.test.mjs"
    "dotfiles/pi/extensions/search-cooldown-core.ts"
  ];
  pi-work = source [
    "tests/pi/headroom-llm-platform.test.mjs"
    "tests/pi/provider-smoke.py"
    "dotfiles/pi/extensions/headroom-llm-platform.ts"
  ];
  nix-format = lib.fileset.toSource {
    inherit root;
    fileset = matching "nix";
  };
  lua-format = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (matching "lua")
      (root + "/dotfiles/nvim/.stylua.toml")
    ];
  };
  shell-syntax = lib.fileset.toSource {
    inherit root;
    fileset = matching "sh";
  };
}
