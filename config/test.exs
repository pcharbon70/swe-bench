import Config
config :swe_bench, token_signing_secret: "6isW/Mn2l3hbgeC5+kwYF6ZkpHhZcBgp"
config :bcrypt_elixir, log_rounds: 1
config :ash, policies: [show_policy_breakdowns?: true], disable_async?: true

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :swe_bench, SweBench.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "swe_bench_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :swe_bench, SweBenchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "U4N7Oyk0Ayikwk8+0nHImkZ4AtbEUj4rAg43OKS+spDXdICBdqXelmoNvSYXSKHb",
  server: false

# In test we don't send emails
config :swe_bench, SweBench.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
