defmodule ShadowMesh.Courier do
  use GenServer, restart: :temporary

  # pass socket in
  def init({conv, group_id, socket}) do
    with {:ok, _pid} <- Registry.register(Courier, conv, []),
         spawn_link(fn -> recv(socket, group_id, conv, 0) end)
    do
      {:ok, {group_id, [], 0, 0,socket, conv}}
    else
      _e -> :ignore
    end
  end

  def send(conv_id, sn, data) do
    case Registry.lookup(Courier, conv_id) do
      [{courier, _value}] ->
        if Process.alive?(courier), do: GenServer.call(courier, {:send, sn, data}), else: {:error, conv_id}
      _ -> 
        {:error, conv_id}
    end
  end

  def handle_call({:send, sn, data}, _, {group_id, queue, sn_acc, current_sn, socket, conv}) do
    sn_acc = if sn==0, do: sn_acc+1, else: sn_acc
    if length(queue) < 65535 do
      case send_queue(Enum.sort([{sn_acc, sn, data}| queue]), current_sn, socket) do 
        :dis_conn->{:stop, "Connection Closed", {:ok, conv}, {group_id, queue, sn_acc, current_sn, socket, conv}}
        {queue, current_sn} -> {:reply, :ok, {group_id, queue, sn_acc, current_sn, socket, conv}}
        :error -> {:stop, "Send_Queue_Failed", {:error, conv}, {group_id, queue, sn_acc, current_sn, socket, conv}}
      end
    else
        {:stop, "Max_Queue", {:error, conv}, {group_id, queue, sn_acc, current_sn, socket, conv}}
    end
  end

  def terminate(reason, {group_id, _queue, _sn_acc, _current_sn, _socket, conv}) do
    Registry.unregister(Courier, conv)
  end


  defp recv(socket, group_id, conv, sn) do
    # error handling? unregister?

    case :gen_tcp.recv(socket, 0) do 
      {:ok, payload} ->
        ShadowMesh.Relay.send(group_id, conv, sn, payload)
        recv(socket, group_id, conv, sn+1)
      {:error, :closed} ->
        ShadowMesh.Relay.dis_conn(conv, group_id)
        GenServer.stop(self)
    end
  end

  defp send_queue([{_sn_acc, sn, :dis_conn} | tail], current_sn, socket) when sn == current_sn do
    :gen_tcp.close(socket)
    :dis_conn
  end
  defp send_queue([{_sn_acc, sn, data} | tail], current_sn, socket) when sn == current_sn do
    case :gen_tcp.send(socket, data) do
      :ok -> send_queue(tail, sn+1, socket)
      _ -> :error
    end
  end

  defp send_queue(queue, current_sn, _socket), do: {queue, current_sn}

end
