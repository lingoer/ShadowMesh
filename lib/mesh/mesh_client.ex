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
    :ok = :gen_tcp.controlling_process(client, pid)
    loop_acceptor(socket)
  end

  def init_conn(client) do
    conv = UUID.uuid1() |> UUID.string_to_binary!
    {:ok, pid} = GenServer.start(ShadowMesh.Courier, {conv, 0, client})
    ShadowMesh.Relay.connect(conv, 0)
    :ok = :gen_tcp.controlling_process(client, pid)
  end

end



