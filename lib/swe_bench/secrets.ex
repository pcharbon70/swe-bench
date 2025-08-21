defmodule SweBench.Secrets do
  @moduledoc """
  Secret provider for AshAuthentication tokens.

  This module provides the signing secret for JWT tokens used in
  authentication. It implements the AshAuthentication.Secret behavior
  to securely provide the token signing secret from application configuration.
  """
  use AshAuthentication.Secret

  def secret_for(
        [:authentication, :tokens, :signing_secret],
        SweBench.Accounts.User,
        _opts,
        _context
      ) do
    Application.fetch_env(:swe_bench, :token_signing_secret)
  end
end
