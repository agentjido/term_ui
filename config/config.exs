import Config

if config_env() == :dev do
  config :git_ops,
    mix_project: Mix.Project.get!(),
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/term_ui",
    manage_mix_version?: true,
    version_tag_prefix: "v"
end

import_config "#{config_env()}.exs"
