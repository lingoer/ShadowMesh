defmodule ShadowMesh.Relay do
  use GenServer, restart: :temporary

  def start_link(state) do
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init({socket, group_id}) do
    {:ok, _owner} = Registry.register(Relay, group_id, [])
    spawn_link(fn -> recv(socket, group_id) end)
    {:ok, {socket, group_id}}
  end


  def send(group_id, conv, sn, payload) do
    relay = pick_relay(group_id)
    GenServer.call(relay, {:send, conv, sn, payload})
  end

  def dis_conn(conv, group_id) do
    relay = pick_relay(group_id)
    GenServer.call(relay, {:dis_conn, conv, 0, ""})
  end

  def connect(conv, group_id) do
    relay = pick_relay(group_id)
    GenServer.call(relay, {:connect, conv, 0, ""})
  end

  # Current SFrame looks like this:
  # +-------+-------+-------+-------+-------+-------+-------+-------+
  # |      cmd      |      conv     |       sn      |      len      |
  # +-------+-------+-------+-------+-------+-------+-------+-------+
  # |                                                               |
  # *                              data                             *
  # |                                                               |
  # +-------+-------+-------+-------+-------+-------+-------+-------+
  defp send_payload(socket, conv, sn, <<chunk::binary-0xffff, rest::binary>>) when rest != "" do
    send_payload(socket, conv, sn, chunk)
    send_payload(socket, conv, sn, rest)
  end

  defp send_payload(socket, conv, sn, payload) do
    len = byte_size(payload)
    p = <<2, conv::binary-16, sn::16, len::16>>
    :ok = :gen_tcp.send(socket, p)
    :ok = :gen_tcp.send(socket, payload)
  end

  defp pick_relay(group_id) do
    relays = Registry.lookup(Relay, group_id)
    [{relay, _}] = Enum.take_random(relays, 1)
    if Process.alive?(relay), do: relay, else: pick_relay(group_id)
  end

  defp recv(socket, group_id) do
    {:ok, header} = :gen_tcp.recv(socket, 21)
    relay(header, group_id, socket)
    recv(socket, group_id)
  end

  defp relay(<<0, conv::binary-16, _sn::16, _len::16>>, group_id, _socket) do
    IO.puts("========================================")
    IO.puts("SEND CONNECT #{inspect(conv)}")
    IO.puts("----------------------------------------")
    with {:ok, socket} <- :gen_tcp.connect('localhost', 8765, [:binary, packet: :raw, active: false]),
         {:ok, server} <- GenServer.start(ShadowMesh.Courier, {conv, group_id, socket}),
         :ok <- :gen_tcp.controlling_process(socket, server) do
      :ok
    else
      _error -> dis_conn(conv, group_id)
    end
  end

  defp relay(<<1, conv::binary-16, _sn::16, _len::16>>, _group_id, _socket) do
    IO.puts("========================================")
    IO.puts("SEND DISSCONNECT: #{inspect(conv)}")
    IO.puts("----------------------------------------")
    with [{courier, _value}] <- Registry.lookup(Courier, conv), do: GenServer.stop(courier)
  end

  defp relay(<<2, conv::binary-16, sn::16, len::16>>, group_id, socket) do
    IO.puts("========================================")
    IO.puts("SEND DATA #{inspect(conv)}")
    IO.puts("----------------------------------------")
    {:ok, data} = :gen_tcp.recv(socket, len)
    case ShadowMesh.Courier.send(conv, sn, data) do
      {:error, _conv} -> dis_conn(conv, group_id)
      _ -> :ok
    end
  end

  def handle_call({:send, conv, sn, payload}, _, {socket, group_id}) do
    send_payload(socket, conv, sn, payload)
    {:reply, :ok, {socket, group_id}}
  end

  def handle_call({:dis_conn, conv, _sn, _payload}, _, {socket, group_id}) do
    :ok = :gen_tcp.send(socket, <<1, conv::binary-16, 0::16, 0::16>>)
    {:reply, :ok, {socket, group_id}}
  end

  def handle_call({:connect, conv, _sn, _payload}, _, {socket, group_id}) do
    :ok = :gen_tcp.send(socket, <<0, conv::binary-16, 0::16, 0::16>>)
    {:reply, :ok, {socket, group_id}}
  end
end

