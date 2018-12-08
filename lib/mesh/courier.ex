defmodule ShadowMesh.Courier do
  use GenServer, restart: :temporary

  # pass socket in
  def init({conv, group_id, socket}) do
    with {:ok, _pid} <- Registry.register(Courier, conv, []),
         spawn_link(fn -> recv(socket, group_id, conv, 0) end)
    do
      IO.puts("Courier Init: #{inspect(conv)}")
      {:ok, {group_id, [], 0, 0,socket, conv}}
    else
      _e -> :ignore
    end
  end

  def send(conv_id, sn, data) do
    case Registry.lookup(Courier, conv_id) do
      [{courier, _value}] ->
        if Process.alive?(courier), do: GenServer.call(courier, {sn, data}), else: {:error, conv_id}
      _ -> 
        IO.puts("No conv?")
        {:error, conv_id}
    end
  end

  def handle_call({:send, sn, data}, _, {group_id, queue, sn_acc, current_sn, socket, conv}) do
    sn_acc = if sn==0, do: sn_acc+1, else: sn_acc
    if length(queue) < 1024 do
      case send_queue(Enum.sort([{sn_acc, sn, data}| queue]), current_sn, socket) do 
        {queue, current_sn} -> {:reply, :ok, {group_id, queue, sn_acc, current_sn, socket}}
        :error -> {:stop, :error, {:error, conv}, {group_id, queue, sn_acc, current_sn, socket, conv}}
      end
    else
        {:stop, :error, {:error, conv}, {group_id, queue, sn_acc, current_sn, socket, conv}}
    end
  end

  def terminate(reason, {_group_id, _queue, _sn_acc, _current_sn, _socket, conv}) do
    IO.puts("Term: #{reason}")
    Registry.unregister(Courier, conv)
  end


  defp recv(socket, group_id, conv, sn) do
    # error handling? unregister?
    {:ok, payload} = :gen_tcp.recv(socket, 0)
    ShadowMesh.Relay.send(group_id, conv, sn, payload)
    recv(socket, group_id, conv, sn+1)
  end

  defp send_queue([{_sn_acc, sn, data} | tail], current_sn, socket) when sn == current_sn do
    case :gen_tcp.send(socket, data) do
      :ok -> send_queue(tail, sn+1, socket)
      _ -> :error
    end
  end

  defp send_queue(queue, current_sn, _socket), do: {queue, current_sn}

end
