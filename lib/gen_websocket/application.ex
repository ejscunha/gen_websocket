defmodule GenWebsocket.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      GenWebsocket.Client.Supervisor
    ]

    opts = [strategy: :one_for_one, name: GenWebsocket.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
