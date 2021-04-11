defmodule GenWebsocket.Client do
  @moduledoc false

  use GenStateMachine, restart: :transient
  alias __MODULE__, as: Data
  alias :gun, as: Gun
  require Logger

  defstruct host: nil,
            port: nil,
            timeout: nil,
            owner: nil,
            owner_monitor_ref: nil,
            transport: nil,
            path: nil,
            headers: nil,
            ws_opts: nil,
            active: nil,
            caller: nil,
            buffer: "",
            recv_queue: :queue.new()

  @type reason() :: any()
  @type opts() :: Keyword.t()

  def start_link(args) do
    GenStateMachine.start_link(__MODULE__, args)
  end

  @spec connect(charlist(), :inet.port_number(), opts(), timeout()) ::
          {:ok, pid()} | {:error, reason()}
  def connect(host, port, opts, timeout)
      when (is_list(host) or is_atom(host) or is_tuple(host)) and (is_integer(port) and port > 0) and
             is_list(opts) and is_integer(timeout) and timeout > 0 do
    case GenWebsocket.Client.Supervisor.start_child({self(), host, port, opts, timeout}) do
      {:ok, client} -> GenStateMachine.call(client, :connect)
      error -> error
    end
  end

  @spec send(pid(), iodata()) :: :ok | {:error, reason()}
  def send(client, data) when is_pid(client) and (is_binary(data) or is_list(data)) do
    GenStateMachine.call(client, {:send, data})
  catch
    :exit, _ -> {:error, :closed}
  end

  @spec recv(pid(), non_neg_integer(), timeout()) :: {:ok, any()} | {:error, reason()}
  def recv(client, length, timeout)
      when is_pid(client) and is_integer(length) and length >= 0 and is_integer(timeout) and
             timeout > 0 do
    GenStateMachine.call(client, {:recv, length, timeout})
  catch
    :exit, _ -> {:error, :closed}
  end

  @spec controlling_process(pid(), pid()) :: :ok | {:error, reason()}
  def controlling_process(client, pid) when is_pid(client) and is_pid(pid) do
    GenStateMachine.call(client, {:owner, pid})
  catch
    :exit, _ -> {:error, :closed}
  end

  @spec close(pid()) :: :ok
  def close(client) when is_pid(client) do
    GenStateMachine.call(client, :close)
  catch
    :exit, _ -> {:error, :closed}
  end

  @spec set_active(pid(), boolean | :once) :: :ok | {:error, reason()}
  def set_active(client, active)
      when is_pid(client) and (is_boolean(active) or active == :once) do
    GenStateMachine.call(client, {:set_active, active})
  catch
    :exit, _ -> {:error, :closed}
  end

  def init({owner, host, port, opts, timeout}) do
    Process.flag(:trap_exit, true)
    ref = Process.monitor(owner)

    {compress, opts} = Keyword.pop(opts, :compress, true)
    {protocols, opts} = Keyword.pop(opts, :protocols, [])
    protocols = Enum.map(protocols, &{&1, :gun_ws_h})

    ws_opts =
      case protocols do
        [] -> %{compress: compress}
        protocols -> %{compress: compress, protocols: protocols}
      end

    args =
      opts
      |> Keyword.put(:host, host)
      |> Keyword.put(:port, port)
      |> Keyword.put(:timeout, timeout)
      |> Keyword.put(:owner, owner)
      |> Keyword.put(:owner_monitor_ref, ref)
      |> Keyword.put_new(:transport, :tcp)
      |> Keyword.put_new(:path, "/")
      |> Keyword.put_new(:headers, [])
      |> Keyword.put_new(:active, false)
      |> Keyword.put(:ws_opts, ws_opts)

    {:ok, :disconnected, struct(Data, args)}
  end

  def handle_event(
        {:call, from},
        :connect,
        :disconnected,
        %Data{
          host: host,
          port: port,
          timeout: timeout,
          transport: transport,
          path: path,
          headers: headers,
          ws_opts: ws_opts
        } = data
      ) do
    Logger.debug("[gen_websocket] Opening connection")

    with start_time <- DateTime.utc_now(),
         {:ok, socket} <-
           Gun.open(host, port, %{transport: transport, connect_timeout: timeout, retry: 0}),
         timeout <- remaining_timeout(timeout, start_time),
         {:ok, _} <- Gun.await_up(socket, timeout) do
      Logger.debug("[gen_websocket] Upgrading connection")
      Gun.ws_upgrade(socket, path, headers, ws_opts)

      {:keep_state, %Data{data | caller: from},
       {:state_timeout, remaining_timeout(timeout, start_time), {:upgrade_timeout, socket, from}}}
    else
      {:error, {:shutdown, :econnrefused}} ->
        Logger.error(
          "[gen_websocket] It was not possible to connect to host #{inspect(host)} on port #{port}"
        )

        error = {:error, :connection_refused}
        {:stop_and_reply, {:shutdown, error}, {:reply, from, error}}

      {:error, {:shutdown, :closed}} ->
        Logger.error(
          "[gen_websocket] It was not possible to connect to host #{inspect(host)} on port #{port}"
        )

        error = {:error, :connection_closed}
        {:stop_and_reply, {:shutdown, error}, {:reply, from, error}}

      {:error, {:shutdown, :nxdomain}} ->
        Logger.error("[gen_websocket] Host #{host} not found")

        error = {:error, :host_not_found}
        {:stop_and_reply, {:shutdown, error}, {:reply, from, error}}

      {:error, {:shutdown, :timeout}} ->
        Logger.error("[gen_websocket] Timeout while trying to connect")

        error = {:error, :timeout}
        {:stop_and_reply, {:shutdown, error}, {:reply, from, error}}

      error ->
        Logger.error(
          "[gen_websocket] There was an error while trying to connect: #{inspect(error)}"
        )

        {:stop_and_reply, {:shutdown, error}, {:reply, from, error}}
    end
  end

  def handle_event({:call, from}, {:send, data}, {:connected, socket}, _) do
    Gun.ws_send(socket, {:binary, data})
    {:keep_state_and_data, {:reply, from, :ok}}
  end

  def handle_event(
        {:call, from},
        {:recv, length, timeout},
        {:connected, _},
        %Data{buffer: buffer, recv_queue: recv_queue} = data
      ) do
    cond do
      length == 0 ->
        {:keep_state, %Data{data | buffer: ""}, {:reply, from, {:ok, buffer}}}

      byte_size(buffer) >= length ->
        <<package::binary-size(length), rest::binary>> = buffer
        {:keep_state, %Data{data | buffer: rest}, {:reply, from, {:ok, package}}}

      true ->
        {:keep_state, %Data{data | recv_queue: :queue.in({from, length}, recv_queue)},
         {:timeout, timeout, {:recv_timeout, {from, length}}}}
    end
  end

  def handle_event(
        {:call, from},
        {:owner, new_owner},
        {:connected, _},
        %Data{owner_monitor_ref: owner_monitor_ref} = data
      ) do
    Process.demonitor(owner_monitor_ref)
    ref = Process.monitor(new_owner)
    {:keep_state, %Data{data | owner: new_owner, owner_monitor_ref: ref}, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, :close, state, _) do
    case state do
      {:connected, socket} -> Gun.close(socket)
      _ -> :ok
    end

    {:stop_and_reply, :normal, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, {:set_active, active}, {:connected, _}, data) do
    {:keep_state, %Data{data | active: active}, {:reply, from, :ok}}
  end

  def handle_event({:call, from}, _, :disconnected, _) do
    {:keep_state_and_data, {:reply, from, {:error, :not_connected}}}
  end

  def handle_event({:call, from}, _, _, _) do
    {:keep_state_and_data, {:reply, from, {:error, :unexpected_command}}}
  end

  def handle_event(:cast, _, _, _) do
    :keep_state_and_data
  end

  def handle_event(
        :info,
        {:gun_upgrade, socket, _, ["websocket"], _},
        :disconnected,
        %Data{caller: caller} = data
      ) do
    Logger.debug("[gen_websocket] Connection upgraded")

    {:next_state, {:connected, socket}, %Data{data | caller: nil},
     {:reply, caller, {:ok, self()}}}
  end

  def handle_event(
        :info,
        {:gun_response, socket, _, _, status, _},
        :disconnected,
        %Data{caller: caller}
      ) do
    Logger.error(
      "[gen_websocket] It was not possible to upgrade connection, response status: #{
        inspect(status)
      }"
    )

    Gun.close(socket)
    error = {:error, {:ws_upgrade_failed, "Response status: #{status}"}}
    {:stop_and_reply, {:shutdown, error}, {:reply, caller, error}}
  end

  def handle_event(
        :info,
        {:gun_error, socket, _, reason},
        :disconnected,
        %Data{caller: caller}
      ) do
    Logger.error(
      "[gen_websocket] Error while trying to upgrade connection, reason: #{inspect(reason)}"
    )

    Gun.close(socket)
    error = {:error, {:ws_upgrade_error, "Reason: #{inspect(reason)}"}}
    {:stop_and_reply, {:shutdown, error}, {:reply, caller, error}}
  end

  def handle_event(
        :info,
        {:gun_down, socket, _, reason, _, _},
        {:connected, socket},
        %Data{owner: owner}
      ) do
    Logger.error("[gen_websocket] Connection went down, reason: #{inspect(reason)}")
    Kernel.send(owner, {:websocket_closed, self()})
    {:stop, {:shutdown, {:error, :connection_down}}}
  end

  def handle_event(
        :info,
        {:gun_ws, _, _, {:binary, frame}},
        {:connected, _},
        %Data{owner: owner, active: active, buffer: buffer, recv_queue: recv_queue} = data
      ) do
    buffer = <<buffer::binary, frame::binary>>

    {buffer, recv_queue} = satisfy_queued_recv(buffer, recv_queue)

    case active do
      true ->
        Kernel.send(owner, {:websocket, self(), buffer})
        {:keep_state, %Data{data | buffer: "", recv_queue: recv_queue}}

      :once ->
        Kernel.send(owner, {:websocket, self(), buffer})
        {:keep_state, %Data{data | active: false, buffer: "", recv_queue: recv_queue}}

      false ->
        {:keep_state, %Data{data | buffer: buffer, recv_queue: recv_queue}}
    end
  end

  def handle_event(:info, {:DOWN, owner_monitor_ref, :process, owner, _}, state, %Data{
        owner: owner,
        owner_monitor_ref: owner_monitor_ref
      }) do
    case state do
      {:connected, socket} -> Gun.close(socket)
      _ -> :ok
    end

    :stop
  end

  def handle_event(:info, msg, _, _) do
    Logger.warn("[gen_websocket] Received unexpected message: #{inspect(msg)}")
    :keep_state_and_data
  end

  def handle_event(:state_timeout, {:upgrade_timeout, socket, caller}, :disconnected, _) do
    Logger.error("[gen_websocket] Timeout while trying to upgrade connection")
    Gun.close(socket)
    error = {:error, :timeout}
    {:stop_and_reply, {:shutdown, error}, {:reply, caller, error}}
  end

  def handle_event(
        :timeout,
        {:recv_timeout, {caller, length} = queued_recv},
        {:connected, _},
        %Data{recv_queue: recv_queue} = data
      ) do
    Logger.warn("[gen_websocket] Timeout while trying to receive data with #{length} bytes")
    recv_queue = :queue.filter(&(&1 != queued_recv), recv_queue)
    {:keep_state, %Data{data | recv_queue: recv_queue}, {:reply, caller, {:error, :timeout}}}
  end

  defp remaining_timeout(current_timeout, start_time),
    do: max(current_timeout - time_since(start_time), 0)

  defp time_since(datetime), do: DateTime.utc_now() |> DateTime.diff(datetime, :millisecond)

  defp satisfy_queued_recv(buffer, recv_queue) do
    recv_list = :queue.to_list(recv_queue)
    {buffer, recv_remaining} = satisfy_recv_items(buffer, recv_list)
    {buffer, :queue.from_list(recv_remaining)}
  end

  defp satisfy_recv_items(buffer, []), do: {buffer, []}

  defp satisfy_recv_items(buffer, [{caller, 0} | remaining_items]) do
    GenStateMachine.reply(caller, {:ok, buffer})
    {"", remaining_items}
  end

  defp satisfy_recv_items(buffer, [{_, length} | _] = items) when byte_size(buffer) < length,
    do: {buffer, items}

  defp satisfy_recv_items(buffer, [{caller, length} | remaining_items]) do
    <<data::binary-size(length), remaining_buffer::binary>> = buffer
    GenStateMachine.reply(caller, {:ok, data})
    satisfy_recv_items(remaining_buffer, remaining_items)
  end
end
