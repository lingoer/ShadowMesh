defmodule ShadowMesh.Server do
  use Task, restart: :permanent

  def start_link(arg) do
    Task.start_link(__MODULE__, :accept, [arg])
  end

  def accept({ip, port}) do
    {:ok, socket} = :gen_tcp.listen(port,[:binary, ip: ip, active: false, keepalive: true, reuseaddr: true])
    loop_acceptor(socket)
  end

  def loop_acceptor(socket) do
    {:ok, socket} = :gen_tcp.accept(socket)
    pid = spawn(fn -> init_conn(socket) end)
    :ok = :gen_tcp.controlling_process(socket, pid)
    loop_acceptor(socket)
  end

  def init_conn(client) do
    {:ok, group_id} = :gen_tcp.recv(client, 1)
    {:ok, pid} = GenServer.start(ShadowMesh.Relay, {client, group_id})
    :ok = :gen_tcp.controlling_process(client, pid)
  end

end


