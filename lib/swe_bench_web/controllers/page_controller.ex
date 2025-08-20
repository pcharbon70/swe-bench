defmodule SweBenchWeb.PageController do
  use SweBenchWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
