defmodule SweBench.Accounts do
  @moduledoc """
  The Accounts domain for managing user accounts and authentication.

  This domain contains resources for users and tokens, providing authentication
  functionality through the Ash Authentication extension.
  """
  use Ash.Domain, otp_app: :swe_bench, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource SweBench.Accounts.Token
    resource SweBench.Accounts.User
  end
end
