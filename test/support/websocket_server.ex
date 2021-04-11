defmodule GenWebsocket.Support.WebsocketServer do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def send(pid, data) do
    GenServer.call(pid, {:send, data})
  end

  def received?(pid, data) do
    GenServer.call(pid, {:received?, data})
  end

  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    delay = Keyword.get(opts, :delay, false)
    path = Keyword.get(opts, :path, "/")
    Kernel.send(self(), :start)
    {:ok, %{port: port, delay: delay, path: path, socket: nil, received: MapSet.new()}}
  end

  def handle_info(:start, %{port: port, delay: delay, path: path} = state) do
    {:ok, listen_socket} = Socket.Web.listen(port)
    {:ok, socket} = Socket.Web.accept(listen_socket)

    if path == socket.path do
      handle_delay(delay)
      Socket.Web.accept!(socket)
      receive_loop(socket, self())
      {:noreply, %{state | socket: socket}}
    else
      Socket.Web.close(socket)
      Kernel.send(self(), :start)
      {:noreply, state}
    end
  end

  def handle_info({:data, data}, %{received: received} = state) do
    {:noreply, %{state | received: MapSet.put(received, data)}}
  end

  def handle_call({:send, data}, _, %{socket: socket} = state) do
    Socket.Web.send(socket, {:binary, data})
    {:reply, :ok, state}
  end

  def handle_call({:received?, data}, _, %{received: received} = state) do
    {:reply, MapSet.member?(received, data), state}
  end

  defp handle_delay(delay) do
    if is_integer(delay) do
      Process.sleep(delay)
    end
  end

  defp receive_loop(socket, server_pid) do
    spawn(fn ->
      case Socket.Web.recv!(socket) do
        {:binary, data} ->
          Kernel.send(server_pid, {:data, data})
          receive_loop(socket, server_pid)

        _ ->
          :ok
      end
    end)
  end
end
