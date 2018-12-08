defmodule ShadowMesh.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false
  require Logger

  use Application

  def start(_type, _args) do
    ShadowMesh.Supervisor.start_link([])
  end
end
