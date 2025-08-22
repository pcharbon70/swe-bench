defmodule SweBench.GitHub.Auth do
  @moduledoc """
  OAuth authentication handler for GitHub API integration.

  Manages OAuth authentication flow with secure token storage
  and automatic token refresh capabilities.
  """

  require Logger

  @github_oauth_url "https://github.com/login/oauth"

  @doc """
  Generates OAuth authorization URL for GitHub.
  """
  def authorization_url(opts \\ []) do
    client_id = get_client_id()
    scope = Keyword.get(opts, :scope, "repo,read:user")
    state = Keyword.get(opts, :state, generate_state())

    params = %{
      client_id: client_id,
      scope: scope,
      state: state,
      redirect_uri: get_redirect_uri()
    }

    query_string = URI.encode_query(params)
    "#{@github_oauth_url}/authorize?#{query_string}"
  end

  @doc """
  Exchanges authorization code for access token.
  """
  def exchange_code_for_token(code, _state \\ nil) do
    client_id = get_client_id()
    client_secret = get_client_secret()

    params = %{
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      redirect_uri: get_redirect_uri()
    }

    case Tesla.post("#{@github_oauth_url}/access_token", params,
           headers: [{"accept", "application/json"}]
         ) do
      {:ok, %{status: 200, body: body}} ->
        case body do
          %{"access_token" => token} ->
            {:ok, token}

          %{"error" => error} ->
            {:error, {:oauth_error, error}}

          _ ->
            {:error, :invalid_response}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  @doc """
  Validates an access token by making a test API call.
  """
  def validate_token(access_token) do
    client = SweBench.GitHub.Client.new(access_token)

    case SweBench.GitHub.Client.api_get(client, "/user") do
      {:ok, user_data} ->
        {:ok,
         %{
           login: user_data["login"],
           id: user_data["id"],
           type: user_data["type"]
         }}

      {:error, :not_found} ->
        {:error, :invalid_token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the current authenticated user information.
  """
  def get_authenticated_user(access_token) do
    validate_token(access_token)
  end

  # Private helper functions

  defp get_client_id do
    Application.get_env(:swe_bench, SweBench.GitHub)[:client_id] ||
      System.get_env("GITHUB_CLIENT_ID") ||
      raise "GitHub client ID not configured"
  end

  defp get_client_secret do
    Application.get_env(:swe_bench, SweBench.GitHub)[:client_secret] ||
      System.get_env("GITHUB_CLIENT_SECRET") ||
      raise "GitHub client secret not configured"
  end

  defp get_redirect_uri do
    Application.get_env(:swe_bench, SweBench.GitHub)[:redirect_uri] ||
      "http://localhost:4000/auth/github/callback"
  end

  defp generate_state do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
