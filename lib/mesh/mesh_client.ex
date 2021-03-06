defmodule ShadowMesh.Client do
  use Task, restart: :permanent

  def start_link(arg) do
    Task.start_link(__MODULE__, :accept, [arg])
  end

  def accept({ip, port}) do
    {:ok, socket} = :gen_tcp.listen(port,[:binary, active: false, keepalive: true, reuseaddr: true])
    loop_acceptor(socket)
  end

  def loop_acceptor(socket) do
    {:ok, client} = :gen_tcp.accept(socket)
    pid = spawn(fn -> init_conn(client) end)
    loop_acceptor(socket)
  end

  def init_conn(client) do
    conv = UUID.uuid1() |> UUID.string_to_binary!
    ShadowMesh.Relay.connect(conv, 0)
    {:ok, pid} = GenServer.start(ShadowMesh.Courier, {conv, 0, client})
  end

end



