defmodule ShadowMesh.Supervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {Registry, keys: :unique, name: Courier},
      {Registry, keys: :duplicate, name: Relay}
      | server_spec 
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def init_relay(ip, port, local_ip, group_id, id) do
    {:ok, socket} = :gen_tcp.connect(ip, port,[:binary, packet: :raw, active: false])
    :gen_tcp.send(socket,<<group_id>>)
    {:ok, pid} = GenServer.start_link(ShadowMesh.Relay , {socket, group_id}, name: id)
    :gen_tcp.controlling_process(socket, pid)
    {:ok, pid}
  end

  def server_spec do
    [{ShadowMesh.Server, {{0,0,0,0}, 2080}}]
  end

  def client_spec do
    [
      %{
        id: :r1,
        start: {__MODULE__, :init_relay, [{127,0,0,1}, 2080, {192,168,10,100}, 0, :r1]}
      },
      %{
        id: :r2,
        start: {__MODULE__, :init_relay, [{127,0,0,1}, 2080, {192,168,10,100}, 0, :r2]}
      },
      {ShadowMesh.Client, {{127, 0, 0, 1}, 8764}}
    ]
  end
end

