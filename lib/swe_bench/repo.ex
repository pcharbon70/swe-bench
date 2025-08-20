defmodule SweBench.Repo do
  use Ecto.Repo,
    otp_app: :swe_bench,
    adapter: Ecto.Adapters.Postgres
end
