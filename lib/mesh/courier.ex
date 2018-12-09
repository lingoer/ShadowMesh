defmodule ShadowMesh.Courier do
  require Logger
  use GenServer, restart: :temporary

  # pass socket in
  def init({conv, group_id, socket}) do
    with {:ok, _pid} <- Registry.register(Courier, conv, []),
         spawn(fn -> recv(socket, group_id, conv, 0) end)
    do
      {:ok, {group_id, %{}, <<0::16>>, socket, conv}}
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

  defp send_queue([{sn, :dis_conn} | tail], nxt_sn, socket) when sn == nxt_sn do
    Logger.info("DISSSSSSS: #{inspect(tail)}")
    :gen_tcp.shutdown(socket, :write)
    {:dis_conn, tail}
  end
  defp send_queue([{<<sn::16>>, data} | tail], <<nxt_sn::16>>, socket) when sn == nxt_sn do
    case :gen_tcp.send(socket, data) do
      :ok ->
        send_queue(tail, <<(sn+1)::16>>, socket)
      e ->
        {:error, [{<<sn::16>>, data}, tail]} #?
    end
  end
  defp send_queue(queue, nxt_sn, _socket) do
    {nxt_sn, queue}
  end

  defp send_queues(queues, [], socket, nxt_sn), do: {nxt_sn, queues}
  defp send_queues(queues, [key| keys], socket, nxt_sn) do
    {nxt_sn, queues} = Map.get_and_update(queues, key, &(send_queue(&1, nxt_sn, socket)))
    send_queues(queues, keys, socket, nxt_sn)
  end

  def handle_call({:send, sn, data}, {sender, _}, {group_id, queues, nxt_sn, socket, conv}) do
    queues = Map.update(queues, sender, [{sn, data}], &(List.insert_at(&1, -1, {sn, data})))
    Logger.info("#{conv}:::::#{}")
    case send_queues(queues, Map.keys(queues), socket, nxt_sn) do
      {:dis_conn, queues} -> {:stop, :normal, :ok, {group_id, queues, nxt_sn, socket, conv}}
      {:error, queues} -> {:stop, "Send_Queue_Failed", {:error, conv}, {group_id, queues, nxt_sn, socket, conv}}
      {nxt_sn, queues} -> 
        Logger.info("#{conv}=======#{inspect(queues)}")
        {:reply, :ok, {group_id, queues, nxt_sn, socket, conv}}
    end
  end

  def terminate(reason, {group_id, _queues, _nxt_sn, _socket, conv}) do
    Registry.unregister(Courier, conv)
  end

  defp recv(socket, group_id, conv, sn) do
    # error handling? unregister?
    case :gen_tcp.recv(socket, 0) do 
      {:ok, payload} ->
        ShadowMesh.Relay.send(group_id, conv, sn, payload)
        recv(socket, group_id, conv, sn+1)
      {:error, :closed} ->
        ShadowMesh.Relay.dis_conn(group_id, conv, sn)
    end
  end
end
